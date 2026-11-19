import AppIntents
import KeyboardStore
import SwiftUI

/// The mic key's working face while the microphone is off: a button for the app's `StartDictation` intent, which
/// iOS performs in iikb in the background, so a dictation starts without opening the app. It draws nothing — the
/// `MicButton` under it shows the mic — and reports the tap (`asked`), so the keyboard can fall back to opening
/// the app if no dictation starts. While the microphone is on, or a dictation is being recorded or written, this
/// is hidden and the key is the plain button it always was: the keyboard starts and stops dictations, and still
/// can't turn the microphone off.
struct DictateButton: View {
    var asked: () -> Void

    var body: some View {
        Button(intent: StartDictation()) {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded { asked() })
    }
}
