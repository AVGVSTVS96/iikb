import SwiftUI

/// One of a setting's values whose data downloads, on one line: its name, and at its right what it does, in
/// one column: Download, Cancel while a bar after the name shows how far it's come, Try Again, Remove once it's here, and
/// the check on the one picked. A tap elsewhere on the row picks it, which for one not here yet is the owner's to decide
/// (a language downloads, then is picked). A newer copy of one that's here comes in with the bar and "Updating" while the
/// old one stays picked. The row keeps its height through all of it.
struct DownloadRow: View {
    enum Phase: Equatable {
        /// Part of iikb: nothing to download or remove.
        case builtIn
        case absent
        case downloading(Double)
        /// Here, and a newer one coming in its place.
        case updating(Double)
        case failed(String)
        case ready
    }

    let title: String
    /// What VoiceOver says after the title: the language's name in the iPhone's own, and the download's size.
    var detail: String? = nil
    let phase: Phase
    let picked: Bool
    let pick: () -> Void
    let download: () -> Void
    let cancel: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            HStack(spacing: 12) {
                Text(title).foregroundStyle(.primary).lineLimit(1).layoutPriority(1)
                status
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityValue(detail ?? "")
            .accessibilityAddTraits(picked ? [.isSelected, .isButton] : .isButton)
            .accessibilityAction(.default, pick)
            ZStack(alignment: .trailing) {
                Pill(title: "Download", of: "", action: {}).hidden().accessibilityHidden(true)
                action
            }
        }
        .row()
        .onTapGesture(perform: pick)
        .animation(.snappy(duration: 0.25), value: phase)
        .animation(.snappy(duration: 0.2), value: picked)
    }

    @ViewBuilder private var status: some View {
        switch phase {
        case .downloading(let done), .updating(let done):
            HStack(spacing: 8) {
                Bar(done: done)
                // As wide as its longest, so the bar is one width however far it's come and whichever it is.
                ZStack(alignment: .trailing) {
                    Text("Updating · 100%").hidden().accessibilityHidden(true)
                    Text(phase == .updating(done) ? "Updating · \(percent(done))" : percent(done))
                        .contentTransition(.identity)
                }
                .monospacedDigit()
                .fixedSize()
            }
            .font(.subheadline)
            .foregroundStyle(Color.appSecondary)
            .lineLimit(1)
        case .failed(let reason):
            Text(reason)
                .font(.subheadline)
                .foregroundStyle(.red)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .trailing)
        default:
            EmptyView()
        }
    }

    private func percent(_ done: Double) -> String { done.formatted(.percent.precision(.fractionLength(0))) }

    /// What the row does at its right, in one column as wide as its buttons: the check on what's picked, Remove on a
    /// download that isn't, and while one comes in Cancel, which an update has no need of.
    @ViewBuilder private var action: some View {
        switch phase {
        case _ where picked, .updating: Radio(picked: true)
        case .builtIn: EmptyView()
        case .ready: Pill(title: "Remove", of: title, action: remove)
        case .absent: Pill(title: "Download", of: title, action: download)
        case .downloading: Pill(title: "Cancel", of: title, action: cancel)
        case .failed: Pill(title: "Try Again", of: title, action: download)
        }
    }
}

/// A small capsule button inside a row, as wide for each of the row's actions, so changing one doesn't move the row.
private struct Pill: View {
    let title: String
    /// The row's title, which VoiceOver says after the action: Download Deutsch.
    let of: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                ForEach(["Download", "Cancel", "Try Again", "Remove"], id: \.self) { Text($0).hidden() }
                Text(title).contentTransition(.opacity)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Color.appPressed, in: .capsule)
        }
        .buttonStyle(CardPress())
        .accessibilityLabel("\(title) \(of)")
    }
}

/// How far a download has come, as a thin track that fills.
private struct Bar: View {
    let done: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.appDivider)
                Capsule().fill(Color.blue).frame(width: max(proxy.size.width * done, 4))
            }
        }
        .frame(height: 4)
        .animation(.linear(duration: 0.15), value: done)
    }
}
