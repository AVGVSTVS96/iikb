import SwiftUI

/// The microphone's switch, alone at a page's trailing edge on every page but Settings and its pages: one glass capsule
/// iikb draws itself, so it sits in the title row on every screen of the Duo. A page's other actions live in the page
/// or in Settings, since iOS moves a bar button to the Duo's side bar on some screens and not others.
struct MicSwitchItem: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) { MicSwitch().endsWithCards() }
            .sharedBackgroundVisibility(.hidden)
    }
}

/// Beside the Duo's side bar iOS sets a title row's last item flush with the safe area, past the cards under it; this
/// moves it back to the cards' edge, `AppStyle.margin` in, wherever it measures closer than that.
private struct EndsWithCards: ViewModifier {
    @Environment(\.safeTrailing) private var safeTrailing
    @State private var trailing = CGFloat.zero

    func body(content: Content) -> some View {
        content
            .offset(x: min(0, safeTrailing - AppStyle.margin - trailing))
            .onGeometryChange(for: CGFloat.self) {
                $0.frame(in: .global).maxX
            } action: {
                trailing = $0
            }
    }
}

extension View {
    fileprivate func endsWithCards() -> some View { modifier(EndsWithCards()) }
}

/// Whether the keyboard starts a dictation in place, as it really is: on, iikb's tab is up (`MicTab`), or where it
/// can't be the microphone is, until you turn it off here; off, the tab goes, and the microphone once what you're
/// saying is written down. The keyboard can't turn it off.
struct MicSwitch: View {
    @State private var flipping: Bool?
    @State private var failure: String?

    var body: some View {
        let listener = Listener.shared
        let on = flipping ?? (listener.tabOpening || listener.isReady && !listener.isTurningMicOff)
        HStack(spacing: 0) {
            Image(systemName: on ? "mic.fill" : "mic.slash.fill")
                .font(.body)
                .foregroundStyle(on ? Color.green : Color.appSecondary)
                .frame(width: 44, height: 44)
                .contentTransition(.symbolEffect(.replace))
                .accessibilityHidden(true)
            Toggle("Microphone", isOn: Binding(get: { on }, set: flip))
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(.blue)
                .accessibilityIdentifier("home-mic")
        }
        // The switch draws its track 1.5pt past its frame's trailing edge; this sits it 8pt in, as it sits top and bottom.
        .padding(.trailing, 9.5)
        .glassEffect(.regular, in: .capsule)
        .alert(
            "Couldn’t Turn On the Microphone",
            isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
        ) {
            Button("Settings") { AppStatus.openSettings() }
            Button("OK", role: .cancel) {}
        } message: {
            Text(failure ?? "")
        }
    }

    private func flip(_ on: Bool) {
        if on, Listener.shared.openTab() { return }
        flipping = on
        Task {
            defer { flipping = nil }
            if !on { return await Listener.shared.turnMicOff() }
            do {
                try await Listener.shared.turnMicOn()
            } catch {
                failure = error.localizedDescription
            }
        }
    }
}
