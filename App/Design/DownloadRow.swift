import SwiftUI

/// One of a setting's values whose data downloads: its name, a line under it that says where it stands, and at its right
/// one control: Download, Cancel beside a bar of how far it's come, Try Again, Remove once it's here, or the radio mark
/// once it's picked, which a picked one's menu removes. A tap elsewhere on the row picks it, which for one not here yet
/// is the owner's to decide (a language downloads, then is picked).
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
        .contextMenu {
            if phase == .ready, picked {
                Button("Remove \(title)", systemImage: "trash", role: .destructive, action: remove)
            }
        }
        .animation(.snappy(duration: 0.25), value: phase)
        .animation(.snappy(duration: 0.2), value: picked)
    }

    @ViewBuilder private var status: some View {
        switch phase {
        case .downloading(let done):
            HStack(spacing: 10) {
                Bar(done: done)
                Text(done.formatted(.percent.precision(.fractionLength(0))))
                    .monospacedDigit()
                    .frame(minWidth: 36, alignment: .trailing)
            }
            .font(.subheadline)
            .foregroundStyle(Color.appSecondary)
            .padding(.vertical, 3)
        case .failed(let reason):
            Text(reason)
                .font(.subheadline)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        default:
            let line = [detail, phase == .builtIn ? "Built in" : phase == .ready ? "Downloaded" : sizeText]
                .compactMap(\.self).joined(separator: " · ")
            Text(line)
                .font(.subheadline)
                .foregroundStyle(Color.appSecondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder private var action: some View {
        switch phase {
        case _ where picked: Radio(picked: true)
        case .builtIn: EmptyView()
        case .absent: Pill(title: "Download", of: title, action: download)
        case .downloading: Pill(title: "Cancel", of: title, action: cancel)
        case .failed: Pill(title: "Try Again", of: title, action: download)
        case .ready: Pill(title: "Remove", of: title, action: remove)
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
