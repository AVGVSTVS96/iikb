import Foundation
import KeyboardStore
import OSLog

/// What voice typing logged in this run of iikb, its last 500 lines and a day back at most, written as `voice.log`
/// beside the transcripts in a build with a backup server, so the backup carries what the microphone and iOS did on
/// the iPhone: its unified log can't be read off it without a cable. The server keeps the file each write replaces, so
/// an iikb that ended keeps its lines there.
nonisolated enum VoiceLog {
    static func write() {
        guard Backup.isBuiltIn, let store = try? OSLogStore(scope: .currentProcessIdentifier),
            let entries = try? store.getEntries(
                at: store.position(date: .now.addingTimeInterval(-86_400)),
                matching: NSPredicate(format: "subsystem == 'com.galateacorp.iikb' AND category == 'voice'"))
        else { return }
        let lines = entries.compactMap { $0 as? OSLogEntryLog }.suffix(500).map {
            "\($0.date.ISO8601Format(.init(includingFractionalSeconds: true))) \($0.composedMessage)\n"
        }
        // file: voice typing's own log lines, for the backup
        try? Data(lines.joined().utf8).write(
            to: .applicationSupportDirectory.appending(path: "voice.log"), options: .atomic)
    }
}
