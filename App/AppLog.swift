import KeyboardStore
import OSLog

/// What this iikb logged in its last day, written as `iikb.log` beside the transcripts in a build with a backup server,
/// so the backup carries what the microphone and iOS did on the iPhone: its unified log can't be read off it without a
/// cable. The server keeps the file each write replaces, so an iikb that ended keeps its lines there.
nonisolated enum AppLog {
    static func write() {
        guard Backup.isBuiltIn, let store = try? OSLogStore(scope: .currentProcessIdentifier),
            let entries = try? store.getEntries(
                at: store.position(date: .now.addingTimeInterval(-86_400)),
                matching: NSPredicate(format: "subsystem == 'com.shahidy.iikb'"))
        else { return }
        let lines = entries.compactMap { $0 as? OSLogEntryLog }.suffix(500).map {
            "\($0.date.ISO8601Format(.init(includingFractionalSeconds: true))) \($0.category) \($0.composedMessage)\n"
        }
        // file: iikb's own log lines, for the backup
        try? Data(lines.joined().utf8).write(to: .applicationSupportDirectory.appending(path: "iikb.log"))
    }
}
