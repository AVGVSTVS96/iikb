import Foundation
import KeyboardStore

/// What this keyboard last showed of each chat, so a chat whose latest line in the list is newer is marked new until you
/// open it. It counts only what the keyboard showed: a message read in Telegram still marks its chat. A chat seen for the
/// first time is taken as read, so nothing is marked new the first time Chats opens.
final class ChatSeen {
    private static let file = StoredFile<[String: [String]]>(
        URL.applicationSupportDirectory.appending(path: "chat-seen.json"))
    /// Each chat's latest line as the list gave it and its newest message as the chat showed it, either of which is
    /// what you saw last.
    private var seen: [String: [String]]

    init() {
        seen = Self.file.read().value ?? [:]
    }

    /// The open chat taken as seen, and the indices in the list of the chats with something newer.
    func update(_ chats: Chats) -> Set<Int> {
        guard chats.listed else { return [] }
        let before = seen
        for chat in chats.list where seen[chat.id] == nil { seen[chat.id] = [chat.line ?? ""] }
        if let open = chats.open, chats.loaded {
            seen[open.id] = [open.line ?? "", chats.messages.last?.text ?? ""]
        }
        if seen != before { Self.file.save(seen) }
        return Set(
            chats.list.indices.filter { index in
                let chat = chats.list[index]
                let line = (chat.line ?? "").trimmingCharacters(in: ["…"])
                return chat != chats.open && !(seen[chat.id] ?? []).contains { $0 == line || $0.hasPrefix(line) }
            })
    }
}
