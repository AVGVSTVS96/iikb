import Foundation
import KeyboardCore
import notify

/// Your snippets and quicklinks, kept as the settings are (`SettingsStore`), since they're made in the app as Sources
/// are: the keyboard reads them without Full Access, as Raycast's does, each side keeps its own copy so they outlive the
/// group's container, and the backup carries them with each side's Preferences. A save tells a keyboard that's up, as
/// the settings' does. A list that can't be read (a build that keeps it another way) is never saved over: it's kept
/// aside under `<key>-unread-<seconds>` first, as `StoredFile` keeps a file.
public enum SnippetStore {
    private static let snippetsKey = "snippets"
    private static let quicklinksKey = "quicklinks"

    public static func snippets(sharing: Bool = true) -> [Snippet] { load(snippetsKey, sharing: sharing) ?? [] }

    public static func quicklinks(sharing: Bool = true) -> [Quicklink] { load(quicklinksKey, sharing: sharing) ?? [] }

    public static func save(_ snippets: [Snippet]) { save(snippets, forKey: snippetsKey) }

    public static func save(_ quicklinks: [Quicklink]) { save(quicklinks, forKey: quicklinksKey) }

    /// Keeps `snippet`, in place of the one with its id.
    public static func keep(_ snippet: Snippet) {
        var all = snippets()
        if let at = all.firstIndex(where: { $0.id == snippet.id }) { all[at] = snippet } else { all.append(snippet) }
        save(all)
    }

    /// Keeps `link`, in place of the one with its id.
    public static func keep(_ link: Quicklink) {
        var all = quicklinks()
        if let at = all.firstIndex(where: { $0.id == link.id }) { all[at] = link } else { all.append(link) }
        save(all)
    }

    /// The list under `key`: nil when there's one that can't be read.
    private static func load<Item: Decodable>(_ key: String, sharing: Bool) -> [Item]? {
        guard let data = SettingsStore.value(forKey: key, sharing: sharing) as? Data else { return [] }
        return try? JSONDecoder().decode([Item].self, from: data)
    }

    private static func save<Item: Codable>(_ items: [Item], forKey key: String) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        if let kept = SettingsStore.value(forKey: key, sharing: true) as? Data,
            (try? JSONDecoder().decode([Item].self, from: kept)) == nil
        {
            SettingsStore.set(kept, forKey: "\(key)-unread-\(Int(Date.now.timeIntervalSince1970))")
        }
        SettingsStore.set(data, forKey: key)
        notify_post(SettingsStore.changed)
    }
}
