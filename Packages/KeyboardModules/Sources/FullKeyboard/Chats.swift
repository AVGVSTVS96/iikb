import Foundation
import KeyboardStore

/// The chats of the extensions you added (docs/extensions.md): every extension's list, pinned chats first, and the open
/// chat's messages, which it asks for again as soon as each answer comes, so the extension holds the request until
/// they change and a reply shows the moment it's written. It stops when the panel closes.
final class Chats {
    nonisolated struct Chat: Hashable, Sendable {
        let service: Extension
        let id: String
        let name: String
        let line: String?
        let pinned: Bool
    }

    nonisolated struct Message: Decodable, Hashable, Sendable {
        let from: String
        let text: String
        var pending: Bool?

        var mine: Bool { from == "me" }
    }

    var changed: () -> Void = {}
    private(set) var list: [Chat] = []
    private(set) var open: Chat?
    private(set) var messages: [Message] = []
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

    func reload() {
        services = ExtensionStore.load()
    }

    /// The panel opened: every extension's chats, then `kept` open again, or the first.
    func start(at kept: String? = nil) {
        stop()
        listed = false
        listing = Task { [weak self, services] in
            var all: [Chat] = [], unreachable: [String] = []
            for service in services {
                if let chats = await Self.list(service) { all += chats } else { unreachable.append(service.name) }
            }
            guard let self, !Task.isCancelled else { return }
            list = all.filter(\.pinned) + all.filter { !$0.pinned }
            listed = true
            problem = unreachable.isEmpty ? nil : "Can’t reach \(unreachable.joined(separator: ", "))."
            pick(list.first { $0.id == kept } ?? list.first)
        }
    }

    func pick(_ chat: Chat?) {
        reading?.cancel()
        if chat != open { (messages, loaded) = ([], false) }
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

    /// Sends `text` to the open chat, shown as pending until the chat's next messages carry it. False when it couldn't.
    func send(_ text: String) async -> Bool {
        guard let chat = open else { return false }
        messages.append(Message(from: "me", text: text, pending: true))
        report()
        let sent = await Self.send(text, to: chat)
        if !sent, open == chat {
            messages.removeAll { $0.pending == true && $0.text == text }
            problem = "Not sent: \(chat.service.name) didn’t answer."
            report()
        }
        return sent
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
            messages = read.messages
            loaded = true
            problem = nil
            report()
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

    nonisolated private static func request(_ url: URL, for service: Extension) -> URLRequest {
        var request = URLRequest(url: url)
        if let token = service.token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return request
    }

    @concurrent nonisolated private static func list(_ service: Extension) async -> [Chat]? {
        guard let listed: Listed = await get(request(service.url, for: service)) else { return nil }
        return listed.chats.map { Chat(service: service, id: $0.id, name: $0.name, line: $0.line, pinned: $0.pinned == true) }
    }

    @concurrent nonisolated private static func read(_ chat: Chat, after version: String?) async -> Read? {
        var url = chat.service.url.appending(component: chat.id)
        if let version { url.append(queryItems: [URLQueryItem(name: "after", value: version)]) }
        return await get(request(url, for: chat.service))
    }

    @concurrent nonisolated private static func send(_ text: String, to chat: Chat) async -> Bool {
        var request = request(chat.service.url.appending(component: chat.id), for: chat.service)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(["text": text, "id": UUID().uuidString])
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
