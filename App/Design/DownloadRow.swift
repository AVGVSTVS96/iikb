import SwiftUI

/// One of a setting's values whose data downloads: its name, a line under it that says where it stands, and at its right
/// one control: Download, Cancel while a bar shows how far it's come, Try Again, Remove once it's here, or the radio mark
/// on the one picked and on what's built in. A tap elsewhere on the row picks it, which for one not here yet is the
/// owner's to decide (a language downloads, then is picked). The control changes in place, so the row keeps its height.
struct DownloadRow: View {
    enum Phase: Equatable {
        /// Part of iikb: nothing to download or remove.
        case builtIn
        case absent
        case downloading(Double)
        case failed(String)
        case ready
    }

    let title: String
    var detail: String? = nil
    /// The download's size in bytes.
    let size: Int
    let phase: Phase
    let picked: Bool
    let pick: () -> Void
    let download: () -> Void
    let cancel: () -> Void
    let remove: () -> Void

    private var sizeText: String { size.formatted(.byteCount(style: .file)) }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).foregroundStyle(.primary)
                status
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(picked ? [.isSelected, .isButton] : .isButton)
            .accessibilityAction(.default, pick)
            action
        }
        .row()
        .onTapGesture(perform: pick)
        .animation(.snappy(duration: 0.25), value: phase)
        .animation(.snappy(duration: 0.2), value: picked)
    }

    @ViewBuilder private var status: some View {
        switch phase {
        case .downloading(let done):
            HStack(spacing: 8) {
                Bar(done: done)
                Text("\(done.formatted(.percent.precision(.fractionLength(0)))) of \(sizeText)")
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
        default:
            Text([detail, phase == .builtIn ? "Built in" : sizeText].compactMap(\.self).joined(separator: " · "))
                .font(.subheadline)
                .foregroundStyle(Color.appSecondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder private var action: some View {
        switch phase {
        case _ where picked, .builtIn: Radio(picked: picked)
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
