import AppIntents
import Foundation
import SwiftUI
import WidgetKit
import notify

@main
struct Controls: WidgetBundle {
    var body: some Widget {
        MicControl()
    }
}

/// iikb's microphone in Control Center, the Lock Screen and the Action button: green while it's on, and a tap turns it
/// off, the way Home's switch does. Off, a tap opens iikb with it on, since iOS starts a microphone only in front.
struct MicControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Mic.control, provider: Provider()) { on in
            ControlWidgetToggle("iikb Mic", isOn: on, action: SetMic()) { on in
                Label(on ? "On" : "Off", systemImage: on ? "mic.fill" : "mic.slash.fill")
            }
            .tint(.green)
        }
        .displayName("iikb Mic")
        .description("Turn iikb’s microphone off, or open iikb with it on.")
    }

    struct Provider: ControlValueProvider {
        let previewValue = true

        func currentValue() async throws -> Bool { Mic.isOn }
    }
}

struct SetMic: SetValueIntent {
    static let title: LocalizedStringResource = "Turn iikb’s Mic On or Off"

    @Parameter(title: "On") var value: Bool

    func perform() async throws -> some IntentResult {
        guard value else {
            notify_post(Mic.off)
            return .result()
        }
        return .result(opensIntent: OpenURLIntent(Mic.link))
    }
}

/// The app's side of these is `Dictation` (`Signal.micOff`, `micIsOn`) and `AppLink.mic` in KeyboardStore, which this
/// extension leaves out for the English data it carries; ArchitectureTests holds the two to the same names.
nonisolated enum Mic {
    static let control = "com.shahidy.iikb.mic"
    static let off = "com.shahidy.iikb.dictation.micoff"
    static let link = URL(string: "iikb://mic")!

    /// The app holds a lock on this file while its microphone is on, which the kernel lets go of however the app ends.
    static var isOn: Bool {
        guard
            let lock = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: "group.com.shahidy.iikb")?
                .appending(path: "Library").appending(path: "mic.lock")
        else { return false }
        let descriptor = open(lock.path, O_RDONLY)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        return flock(descriptor, LOCK_SH | LOCK_NB) != 0
    }
}
