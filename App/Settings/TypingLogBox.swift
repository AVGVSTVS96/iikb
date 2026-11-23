import KeyboardStore
import SwiftUI

struct TypingLogBox: View {
    private let model = SettingsModel.shared
    @State private var saved: [SessionLogs.Saved] = []
    @State private var confirmsDelete = false

    var body: some View {
        Box(
            header: "Typing Log",
            footer:
                "Keeps each session on this \(ThisDevice.name) so you can share one that went wrong: what you type, the field’s text and app, your learned words, snippets, text replacements and contact names. Never in password, code or card fields, never backed up. Turning it off deletes it. Needs Full Access."
        ) {
            ToggleRow(
                title: "Keep a Typing Log",
                isOn: Binding {
                    model.settings.sessionLog
                } set: { on in
                    model.update { $0.sessionLog = on }
                    guard !on else { return }
                    SessionLogs.deleteAll()
                    saved = []
                })
            ForEach(saved) { session in
                ShareLink(item: session.url) {
                    HStack {
                        RowText(
                            title: session.date.formatted(date: .abbreviated, time: .shortened),
                            detail: session.size.formatted(.byteCount(style: .file)))
                        Spacer()
                        Image(systemName: "square.and.arrow.up").font(.subheadline.weight(.semibold))
                    }
                    .row()
                }
            }
            if !saved.isEmpty {
                ActionRow(title: "Delete Typing Log", role: .destructive) { confirmsDelete = true }
            }
        }
        .onAppear { saved = SessionLogs.saved() }
        .confirmationDialog(
            "Delete every typing session on this \(ThisDevice.name)?", isPresented: $confirmsDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                SessionLogs.deleteAll()
                saved = []
            }
        }
    }
}
