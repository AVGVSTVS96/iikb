import ActivityKit
import AppIntents
import Foundation
import SwiftUI
import WidgetKit
import notify

/// The dictation session's face on the Lock Screen and in the Dynamic Island: whether iikb is recording, and an
/// End that turns the microphone off, as the app's mic switch does. The app keeps it up while its microphone is on
/// (`Listener`, App/Voice). The attributes are the app's `DictationSessionAttributes` in KeyboardStore, spelled
/// here because this extension leaves KeyboardStore out for the English data it carries; ArchitectureTests holds
/// the two spellings to one shape, since the state crosses as JSON.
nonisolated struct DictationSessionAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable {
        var listening: Bool
    }
}

struct SessionActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DictationSessionAttributes.self) { context in
            HStack {
                Label(
                    context.state.listening ? "Listening…" : "iikb’s mic is on",
                    systemImage: context.state.listening ? "mic.fill" : "mic")
                Spacer()
                Button(intent: EndSession()) { Text("End") }
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.listening ? "Listening" : "Mic on", systemImage: "mic.fill")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Button(intent: EndSession()) { Text("End") }
                }
            } compactLeading: {
                Image(systemName: "mic.fill")
                    .foregroundStyle(context.state.listening ? Color.red : Color.green)
            } compactTrailing: {
                EmptyView()
            } minimal: {
                Image(systemName: "mic.fill")
                    .foregroundStyle(context.state.listening ? Color.red : Color.green)
            }
        }
    }
}

/// Ends the dictation session: the microphone goes off as Control Center's iikb Mic turned off does — what you're
/// saying is kept and written down first — by the same `micOff` signal (`Mic.off`).
struct EndSession: AppIntent {
    static let title: LocalizedStringResource = "Turn iikb’s Mic Off"

    func perform() async throws -> some IntentResult {
        notify_post(Mic.off)
        return .result()
    }
}
