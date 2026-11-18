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

/// Where the actions show: a row of keys of their own above the letters, at the bar's left as its tools, or nowhere.
public enum ActionPlace: Hashable, Sendable {
    case row, bar, none
}

extension KeyboardSettings {
    /// The action row where it's on, an iPhone's only, upright unless it's kept in landscape too, else the bar's left;
    /// without it, the bar's left with Predictive Text off, in the suggestions' room.
    public func actionPlace(phone: Bool, landscape: Bool) -> ActionPlace {
        if actionRow, phone { return !landscape || actionRowInLandscape ? .row : .bar }
        return predictiveText ? .none : .bar
    }
}
