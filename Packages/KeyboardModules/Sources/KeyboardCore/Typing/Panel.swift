/// A tool that opens over the bar: its results on top and a search field under them, which the keys type into while
/// it's open (docs/design.md, "Panels").
public enum Panel: String, Hashable, Sendable, CaseIterable {
    case emoji
    case gif
    case clipboard
    /// What you dictated.
    case transcripts
    /// The chats of the extensions you added. It opens above the bar rather than in its place, and the keys type into a
    /// message line as they do into any field (`LineDocument`), so the engine never opens it.
    case chats
    /// Text Styles and Change Case: what you wrote in Unicode's styles or another case (`Rewrite`).
    case textStyles
    case changeCase

    /// Every tool, in the order Customize Actions lists them: the actions you can pick for the action row and the bar.
    public static let tools: [Panel] = [.emoji, .gif, .transcripts, .clipboard, .textStyles, .changeCase]

    /// The actions before you pick any: the menu's panels, the emoji key being where emoji are.
    public static let standardActions: [Panel] = [.gif, .transcripts, .clipboard]
}
