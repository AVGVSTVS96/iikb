import Foundation
import KeyboardStore

extension Backup {
    /// Sends the app's files and the group's in the background.
    static func syncApp() {
        sync(app + group, skip: unwritten)
        Task { await PersonalNetwork.fetch() }
    }

    /// Sends them with what voice typing logged up to now (`VoiceLog`), which takes seconds to read, so iOS is asked to
    /// let it finish as iikb goes away.
    static func syncAppAndVoiceLog() {
        let skip = unwritten
        ProcessInfo.processInfo.performExpiringActivity(withReason: "Backing up iikb") { expired in
            guard !expired else { return }
            VoiceLog.write()
            sync(app + group, skip: skip)
        }
    }

    /// Sends the app's files and the group's and says how it went.
    static func sendApp() async -> Outcome? {
        await PersonalNetwork.fetch()
        return await send(app + group, skip: unwritten)
    }

    /// Recordings still being made, which go once written down.
    private static var unwritten: @Sendable (String) -> Bool {
        let written = Set(Transcripts.shared.all.map { "app/recordings/\($0.id.uuidString).wav" })
        return { $0.hasPrefix("app/recordings/") && !written.contains($0) }
    }
}
