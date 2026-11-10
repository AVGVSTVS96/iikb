import Foundation

/// A service whose chats the keyboard opens from the bar, to read them and write in them (docs/extensions.md).
nonisolated public struct Extension: Codable, Hashable, Sendable, Identifiable {
    public var name: String
    public var url: URL
    public var token: String?
    public var id: String { name + url.absoluteString }

    public init(name: String, url: URL, token: String? = nil) {
        self.name = name
        self.url = url
        self.token = token
    }

    /// `iikb://extension?name=…&url=…&token=…`, the link an extension gives you to add it.
    public init?(link: URL) {
        guard link.scheme == "iikb", link.host() == "extension",
            let items = URLComponents(url: link, resolvingAgainstBaseURL: false)?.queryItems,
            let name = items.first(where: { $0.name == "name" })?.value, !name.isEmpty,
            let url = items.first(where: { $0.name == "url" })?.value.flatMap(URL.init(string:)), Source.allows(url)
        else { return nil }
        self.init(name: name, url: url, token: items.first { $0.name == "token" }?.value)
    }
}

/// The extensions you added in the app, kept like every other setting.
public enum ExtensionStore {
    private static let key = "extensions"

    public static func load(sharing: Bool = true) -> [Extension] {
        (SettingsStore.value(forKey: key, sharing: sharing) as? Data).flatMap {
            try? JSONDecoder().decode([Extension].self, from: $0)
        } ?? []
    }

    public static func save(_ extensions: [Extension]) {
        guard let data = try? JSONEncoder().encode(extensions) else { return }
        SettingsStore.set(data, forKey: key)
    }

    /// Adds `extension`, in place of one with the same name or address, since one address serves one list of chats.
    public static func add(_ added: Extension) {
        save(load().filter { $0.name != added.name && $0.url != added.url } + [added])
    }
}

/// What you sent in a chat that its extension hasn't answered for yet, kept in the keyboard's own container, so a send
/// outlives the keyboard that began it, under one id, so the extension takes it once however often it's sent.
nonisolated public struct UnsentMessage: Codable, Hashable, Sendable {
    public let service: String
    public let chat: String
    public let id: String
    public let text: String
    /// The photos sent with it, in order.
    public let photos: [UnsentPhoto]?

    public init(
        service: String, chat: String, id: String = UUID().uuidString, text: String, photos: [UnsentPhoto] = []
    ) {
        self.service = service
        self.chat = chat
        self.id = id
        self.text = text
        self.photos = photos.isEmpty ? nil : photos
    }
}

/// A photo to send, as a JPEG made small enough to send (`UnsentStore.keep`), in the keyboard's container beside the
/// unsent messages.
nonisolated public struct UnsentPhoto: Codable, Hashable, Sendable {
    public let name: String
    public let width: Int
    public let height: Int

    public var url: URL { UnsentStore.photos.appending(path: name) }
}

/// The unsent messages, oldest first. Each change reads the file again, since every app's keyboard keeps its own.
nonisolated public enum UnsentStore {
    private static let file = StoredFile<[UnsentMessage]>(
        URL.applicationSupportDirectory.appending(path: "chat-unsent.json"))
    /// The photos picked to send, kept a day after they're picked, so a sent one still shows in its chat until the
    /// extension's copy comes.
    public static let photos = URL.applicationSupportDirectory.appending(path: "chat-photos")

    public static func load() -> [UnsentMessage] {
        file.read().value ?? []
    }

    public static func add(_ message: UnsentMessage) {
        file.save(load() + [message])
    }

    public static func remove(_ message: UnsentMessage) {
        file.save(load().filter { $0 != message })
    }

    /// Keeps a photo's JPEG to send, nil when it can't be written.
    public static func keep(_ jpeg: Data, width: Int, height: Int) -> UnsentPhoto? {
        let photo = UnsentPhoto(name: UUID().uuidString + ".jpg", width: width, height: height)
        try? FileManager.default.createDirectory(at: photos, withIntermediateDirectories: true)
        guard (try? jpeg.write(to: photo.url, options: .atomic)) != nil else { return nil }  // file: photos to send
        return photo
    }

    /// Drops the photos picked over a day ago that no unsent message holds.
    public static func prune(keeping kept: Set<String> = []) {
        let held = kept.union(load().flatMap { $0.photos ?? [] }.map(\.name))
        let old = Date.now.addingTimeInterval(-86_400)
        let files =
            (try? FileManager.default.contentsOfDirectory(
                at: photos, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in files where !held.contains(file.lastPathComponent) {
            let made = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let made, made < old { try? FileManager.default.removeItem(at: file) }
        }
    }
}
