import Foundation
import KeyboardStore
import OSLog

/// What voice typing logged in this run of iikb, with what the keyboard's own dictations did (`KeyboardVoiceLog`), its
/// last 500 lines and a day back at most, written as `voice.log` beside the transcripts in a build with a backup server,
/// so the backup carries what the microphone and iOS did on the iPhone: its unified log can't be read off it without a
/// cable. The server keeps the file each write replaces, so an iikb that ended keeps its lines there.
nonisolated enum VoiceLog {
    static func write() {
        guard Backup.isBuiltIn, let store = try? OSLogStore(scope: .currentProcessIdentifier),
            let entries = try? store.getEntries(
                at: store.position(date: .now.addingTimeInterval(-86_400)),
                matching: NSPredicate(format: "subsystem == 'com.galateacorp.iikb' AND category == 'voice'"))
        else { return }
        let day = Date.now.addingTimeInterval(-86_400)
        let own = entries.compactMap { $0 as? OSLogEntryLog }.map { (at: $0.date, text: $0.composedMessage) }
        let keyboard = KeyboardVoiceLog.read().filter { $0.at > day }.map { (at: $0.at, text: "keyboard: \($0.text)") }
        let lines = (own + keyboard).sorted { $0.at < $1.at }.suffix(500).map {
            "\($0.at.ISO8601Format(.init(includingFractionalSeconds: true))) \($0.text)\n"
        }
        // file: voice typing's own log lines, for the backup
        try? Data(lines.joined().utf8).write(
            to: .applicationSupportDirectory.appending(path: "voice.log"), options: .atomic)
    }
}
