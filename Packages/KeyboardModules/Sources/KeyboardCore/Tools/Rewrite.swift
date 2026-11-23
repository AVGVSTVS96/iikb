/// What Text Styles and Change Case do to the text they act on (`TypingEngine.rewriting`).
public enum Rewrite: Codable, Hashable, Sendable {
    case style(TextStyle)
    case letterCase(LetterCase)

    /// The name, written as the rewrite writes it ("𝐁𝐨𝐥𝐝 𝐒𝐞𝐫𝐢𝐟", "camelCase").
    public var title: String {
        switch self {
        case .style(let style): style.apply(to: style.name)
        case .letterCase(let letterCase): letterCase.name
        }
    }

    public var name: String {
        switch self {
        case .style(let style): style.name
        case .letterCase(let letterCase): letterCase.name
        }
    }

    public func apply(to text: String) -> String {
        apply(to: text, plain: TextStyle.plain(text)).text
    }

    /// The rewrite of `text`, and of the plain letters it was styled from: a style starts over from those, so a style
    /// that can't hold a letter's case (Squared) doesn't lose it for the next one.
    func apply(to text: String, plain: String) -> (text: String, plain: String) {
        switch self {
        case .style(let style): (style.apply(to: plain), plain)
        case .letterCase(let letterCase): (letterCase.apply(to: text), letterCase.apply(to: plain))
        }
    }
}

/// What a rewrite wrote, from which plain letters, and the text around the caret it left.
struct Rewritten: Hashable, Sendable {
    var text: String
    var plain: String
}

extension Panel {
    /// What the panel's results do, for Text Styles and Change Case, matching `query` by name.
    public func rewrites(matching query: String = "") -> [Rewrite] {
        let all: [Rewrite] =
            switch self {
            case .textStyles: TextStyle.all.map(Rewrite.style)
            case .changeCase: LetterCase.allCases.map(Rewrite.letterCase)
            default: []
            }
        let words = query.lowercased().split(separator: " ")
        return all.filter { rewrite in words.allSatisfy { rewrite.name.lowercased().contains($0) } }
    }
}
