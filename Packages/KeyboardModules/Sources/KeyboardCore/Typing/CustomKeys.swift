/// Raycast's Custom Keys, as iikb has them (docs/design.md, "Custom Keys").

/// The More button at the bar's left, which opens the menu, or nothing there, the suggestions taking its room and the
/// menu's panels opening only from your actions. An iPad keeps its button.
public enum LeadingButton: String, CaseIterable, Hashable, Sendable {
    case menu, hidden

    public var title: String {
        switch self {
        case .menu: "Menu"
        case .hidden: "Hidden"
        }
    }
}

/// A key that can sit beside the space bar, on either side of it.
public enum BottomKey: String, CaseIterable, Hashable, Sendable {
    case emoji, space, period, snippet

    /// Emoji where Apple's is, and the period and snippet keys after space.
    public static let standard: [BottomKey] = [.emoji, .space, .period, .snippet]

    /// `order` with each key once, space included, any missing put where `standard` has them.
    public static func arranged(_ order: [BottomKey]) -> [BottomKey] {
        var seen = Set<BottomKey>()
        var keys = order.filter { seen.insert($0).inserted }
        for key in standard where !seen.contains(key) {
            let after = standard.prefix { $0 != key }.last { keys.contains($0) }
            keys.insert(key, at: after.flatMap { keys.firstIndex(of: $0) }.map { $0 + 1 } ?? 0)
        }
        return keys
    }
}

extension KeyboardSettings {
    /// Whether the bar holds your actions at its left: where they're put there, or with Predictive Text off, in the
    /// suggestions' room.
    public var showsActions: Bool {
        actionsInBar || !predictiveText
    }
}
