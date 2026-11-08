/// A tool that opens over the bar: its results on top and a search field under them, which the keys type into while
/// it's open (docs/design.md, "Panels").
public enum Panel: Hashable, Sendable, CaseIterable {
    case emoji
    case gif
    case clipboard
    /// What you dictated.
    case transcripts
    /// The chats of the extensions you added. It opens above the bar rather than in its place, and the keys type into a
    /// message line as they do into any field (`LineDocument`), so the engine never opens it.
    case chats

    /// The panels, in the order of their tools in the bar.
    public static let tools: [Panel] = [.emoji, .gif, .transcripts, .clipboard]
}
