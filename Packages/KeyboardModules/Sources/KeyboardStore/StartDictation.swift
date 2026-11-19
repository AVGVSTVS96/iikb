import ActivityKit
import AppIntents
import Foundation

/// The dictation session's Live Activity: up while the app has the microphone on, shown by Controls
/// (`SessionActivity`), whose copy of these attributes is spelled there because that extension leaves
/// KeyboardStore out; ArchitectureTests holds the two spellings to one shape. Its being up is also what lets iOS
/// start the microphone in the app's process in the background (`StartDictation`).
nonisolated public struct DictationSessionAttributes: ActivityAttributes, Sendable {
    nonisolated public struct ContentState: Codable, Hashable, Sendable {
        /// A dictation is being recorded now, not only the microphone held on for the next one.
        public var listening: Bool

        public init(listening: Bool) {
            self.listening = listening
        }
    }

    public init() {}
}

/// Asking for a dictation with the microphone off, from the keyboard's mic key (a button for this intent,
/// `DictateButton`) or from Siri and Shortcuts: iOS performs it in iikb's process in the background
/// (`openAppWhenRun` is false), where it puts the session's Live Activity up first — with an activity up, iOS
/// lets the process start the microphone — then tells `Listener` (the `intentStart` signal) to start, and waits
/// until the status says it's listening, so the process stays until the recording itself holds it. This only
/// starts a dictation: the app alone turns the microphone off.
public struct StartDictation: AudioRecordingIntent, LiveActivityIntent {
    public static let title: LocalizedStringResource = "Start Dictation"
    public static let description: IntentDescription =
        "Starts a dictation in iikb, without opening the app."
    public static let openAppWhenRun = false

    public init() {}

    public func perform() async throws -> some IntentResult {
        if Activity<DictationSessionAttributes>.activities.isEmpty {
            _ = try? Activity<DictationSessionAttributes>.request(
                attributes: DictationSessionAttributes(),
                content: ActivityContent(
                    state: DictationSessionAttributes.ContentState(listening: false), staleDate: nil))
        }
        Dictation.send(.intentStart)
        for _ in 0..<50 where !Dictation.status.listening {
            try? await Task.sleep(for: .milliseconds(100))  // timer: intent answer
        }
        return .result()
    }
}

/// Siri's and Shortcuts' way to the same ask.
public struct IikbShortcuts: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartDictation(),
            phrases: [
                "Dictate with \(.applicationName)", "Start a dictation with \(.applicationName)",
            ],
            shortTitle: "Start Dictation",
            systemImageName: "mic.fill")
    }
}
