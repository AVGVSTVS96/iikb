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

    /// Adds `extension`, in place of one with the same name.
    public static func add(_ added: Extension) {
        save(load().filter { $0.name != added.name } + [added])
    }
}
