import Foundation
import KeyboardStore

/// The chats of the extensions you added (docs/extensions.md): every extension's list, pinned chats first, and the open
/// chat's messages, which it asks for again as soon as each answer comes, so the extension holds the request until
/// they change and a reply shows the moment it's written. It stops when the panel closes. What you send is kept until
/// its extension has it (`UnsentStore`), and goes again whenever the keyboard appears or an extension answers.
final class Chats {
    nonisolated struct Chat: Hashable, Sendable {
        let service: Extension
        let id: String
        let name: String
        let line: String?
        let pinned: Bool

        func holds(_ message: UnsentMessage) -> Bool { message.service == service.id && message.chat == id }
    }

    nonisolated struct Message: Decodable, Hashable, Sendable {
        let from: String
        let text: String
        var pending: Bool?
        var files: [File]?

        var mine: Bool { from == "me" }

        /// A file sent with the message, at `url` relative to the extension's address.
        struct File: Decodable, Hashable, Sendable {
            let name: String
            let url: String
            var type: String?
        }
    }

    var changed: () -> Void = {}
    private(set) var list: [Chat] = []
    private(set) var open: Chat?
    /// The open chat as its extension last gave it, then what you sent that the extension doesn't have yet.
    var messages: [Message] {
        guard let open else { return [] }
        return said + unsent.filter { open.holds($0) }.map { Message(from: "me", text: $0.text, pending: true) }
    }
    private var said: [Message] = []
    /// Each chat's last answer, by its extension and id, so switching back to a chat shows it at once.
    private var seen: [String: [Message]] = [:]
    private var unsent: [UnsentMessage] = []
    /// Counts the open chat's answers, so a send knows whether one came while it was on its way.
    private var answers = 0
    /// The open chat's messages have come at least once.
    private(set) var loaded = false
    /// Every extension has answered with its chats, or failed to.
    private(set) var listed = false
    /// Why something can't be shown or sent, like an extension that doesn't answer.
    private(set) var problem: String?
    /// Counts every change, so the panel redraws only when there's one.
    private(set) var revision = 0
    private(set) var services: [Extension] = []
    private var listing: Task<Void, Never>?
    private var reading: Task<Void, Never>?
    private var sending: Task<Void, Never>?

    func reload() {
        services = ExtensionStore.load()
        deliver()
    }

    /// Every extension's chats, pinned first, kept on show until the new list comes; then, `opening` them (the panel
    /// rather than the menu's shelf), `kept` open again, or the first. A `kept` chat already on show opens at once.
    func start(at kept: String? = nil, opening: Bool = true) {
        stop()
        if list.isEmpty { listed = false }
        if opening, let shown = list.first(where: { $0.id == kept }) { pick(shown) }
        listing = Task { [weak self, services] in
            var all: [Chat] = []
            var unreachable: [String] = []
            for service in services {
                if let chats = await Self.list(service) { all += chats } else { unreachable.append(service.name) }
            }
            guard let self, !Task.isCancelled else { return }
            list = all.filter(\.pinned) + all.filter { !$0.pinned }
            listed = true
            problem = unreachable.isEmpty ? nil : "Can’t reach \(unreachable.joined(separator: ", "))."
            deliver()
            if opening { pick(list.first { $0.id == kept } ?? list.first) } else { report() }
        }
    }

    func pick(_ chat: Chat?) {
        reading?.cancel()
        if chat != open {
            let last = chat.flatMap { seen[$0.service.id + $0.id] }
            (said, loaded) = (last ?? [], last != nil)
        }
        open = chat
        report()
        guard let chat else { return }
        reading = Task { [weak self] in await self?.follow(chat) }
    }

    func stop() {
        listing?.cancel()
        reading?.cancel()
        (listing, reading) = (nil, nil)
    }

    /// Keeps `text` for the open chat, shown as pending, and sends it. False with no chat open to keep it for.
    func send(_ text: String) -> Bool {
        guard let chat = open else { return false }
        UnsentStore.add(UnsentMessage(service: chat.service.id, chat: chat.id, text: text))
        deliver()
        return true
    }

    /// Sends what's kept, oldest first, each to its chat's extension until the extension has it. A chat whose message
    /// can't go waits for the next send, answer or keyboard, and the other chats' go on. One the open chat's next
    /// answer hasn't shown yet stays in it as pending.
    private func deliver() {
        let kept = UnsentStore.load()
        if kept != unsent {
            unsent = kept
            report()
        }
        guard sending == nil else { return }
        sending = Task { [weak self] in
            var waiting: Set<String> = []
            while let self, let (next, service) = oldest(outside: waiting) {
                let answered = answers
                guard await Self.send(next, to: service) else {
                    waiting.insert(next.service + next.chat)
                    problem = "Can’t reach \(service.name). What you sent is kept and goes again."
                    continue
                }
                UnsentStore.remove(next)
                unsent.removeAll { $0 == next }
                if let open, open.holds(next), answers == answered {
                    said.append(Message(from: "me", text: next.text, pending: true))
                }
                report()
            }
            self?.sending = nil
            self?.report()
        }
    }

    /// The oldest kept message of a chat not in `waiting`, with the extension it goes to.
    private func oldest(outside waiting: Set<String>) -> (UnsentMessage, Extension)? {
        for message in unsent where !waiting.contains(message.service + message.chat) {
            if let service = services.first(where: { $0.id == message.service }) { return (message, service) }
        }
        return nil
    }

    private func follow(_ chat: Chat) async {
        var version: String?
        while !Task.isCancelled {
            let read = await Self.read(chat, after: version)
            guard !Task.isCancelled, open == chat else { return }
            guard let read else {
                problem = "Can’t reach \(chat.service.name). Pick the chat to try again."
                return report()
            }
            guard read.version != version || problem != nil else { continue }
            version = read.version
            said = read.messages
            seen[chat.service.id + chat.id] = said
            answers += 1
            loaded = true
            problem = nil
            report()
            deliver()
        }
    }

    private func report() {
        revision += 1
        changed()
    }

    nonisolated private struct Listed: Decodable {
        struct Item: Decodable {
            let id: String
            let name: String
            var line: String?
            var pinned: Bool?
        }

        let chats: [Item]
    }

    nonisolated private struct Read: Decodable {
        let version: String
        let messages: [Message]
    }

    nonisolated private static let session = URLSession(configuration: .ephemeral)

    /// Where the open chat's extension serves `file`: its address, or one under the extension's.
    func url(of file: Message.File) -> URL? {
        guard let service = open?.service else { return nil }
        if let url = URL(string: file.url), url.scheme != nil { return url }
        let base = service.url.absoluteString
        return URL(string: (base.hasSuffix("/") ? base : base + "/") + file.url)
    }

    /// A file's bytes from the open chat's extension, with its token.
    func data(at url: URL) async -> Data? {
        guard let service = open?.service else { return nil }
        return await Self.data(Self.request(url, for: service))
    }

    @concurrent nonisolated private static func data(_ request: URLRequest) async -> Data? {
        guard let (data, response) = try? await session.data(for: request),
            let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status)
        else { return nil }
        return data
    }

    nonisolated private static func request(_ url: URL, for service: Extension) -> URLRequest {
        var request = URLRequest(url: url)
        if let token = service.token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return request
    }

    @concurrent nonisolated private static func list(_ service: Extension) async -> [Chat]? {
        guard let listed: Listed = await get(request(service.url, for: service)) else { return nil }
        return listed.chats.map {
            Chat(service: service, id: $0.id, name: $0.name, line: $0.line, pinned: $0.pinned == true)
        }
    }

    @concurrent nonisolated private static func read(_ chat: Chat, after version: String?) async -> Read? {
        var url = chat.service.url.appending(component: chat.id)
        if let version { url.append(queryItems: [URLQueryItem(name: "after", value: version)]) }
        return await get(request(url, for: chat.service))
    }

    @concurrent nonisolated private static func send(_ message: UnsentMessage, to service: Extension) async -> Bool {
        var request = request(service.url.appending(component: message.chat), for: service)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(["text": message.text, "id": message.id])
        guard let (_, response) = try? await session.data(for: request) else { return false }
        return (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
    }

    @concurrent nonisolated private static func get<Answer: Decodable>(_ request: URLRequest) async -> Answer? {
        guard let (data, response) = try? await session.data(for: request),
            let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status)
        else { return nil }
        return try? JSONDecoder().decode(Answer.self, from: data)
    }
}
