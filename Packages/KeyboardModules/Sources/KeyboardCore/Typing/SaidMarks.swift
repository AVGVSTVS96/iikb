/// Punctuation said by name, as every dictation does: "Hi Sam comma thanks period" is "Hi Sam, thanks.", and "new
/// line" and "new paragraph" break the line. A name stays a word where it's one, after "a", "the" and their like ("the
/// grace period", "a new line of shoes") or before "of" ("a period of time"). Parakeet's own marks around a name give
/// way to it, and a sentence it ends starts with a capital.
enum SaidMarks {
    private static let marks: [(words: [String], mark: String)] = [
        (["new", "paragraph"], "\n\n"), (["new", "line"], "\n"), (["newline"], "\n"),
        (["question", "mark"], "?"), (["exclamation", "point"], "!"), (["exclamation", "mark"], "!"),
        (["full", "stop"], "."), (["period"], "."), (["comma"], ","), (["semicolon"], ";"), (["colon"], ":"),
    ]

    private static let nouns: Set<String> = [
        "a", "an", "the", "this", "that", "each", "every", "per", "my", "your", "his", "her", "our", "their", "its",
        "no", "any", "some", "one", "grace", "trial", "waiting", "time", "oxford", "serial", "same", "which", "what",
    ]

    static func written(_ text: [Character]) -> [Character] {
        var text = pathsJoined(text)
        var searched = 0
        while let (range, mark) = said(in: text, from: searched) {
            var start = range.lowerBound
            var end = range.upperBound
            while start > 0, text[start - 1] == " " || ",.".contains(text[start - 1]) { start -= 1 }
            while end < text.count, text[end] == " " || ",.!?;:".contains(text[end]) { end += 1 }
            var with = Array(mark)
            if mark == "\n\n", start > 0, Words.isWordCharacter(text[start - 1]) { with.insert(".", at: 0) }
            if end < text.count, !mark.hasSuffix("\n") { with.append(" ") }
            if end < text.count, ".!?\n".contains(mark.last!), text[end].isLowercase {
                text[end] = Character(text[end].uppercased())
            }
            text.replaceSubrange(start..<end, with: with)
            searched = start + with.count
        }
        return text
    }

    private static func said(in text: [Character], from: Int) -> (Range<Int>, String)? {
        let words = Words.ranges(in: text)
        let spelled = { (index: Int) in Words.plain(String(text[words[index]]).lowercased()) }
        for index in words.indices where words[index].lowerBound >= from && index > 0 {
            guard !nouns.contains(spelled(index - 1)) else { continue }
            for (said, mark) in marks where index + said.count <= words.count {
                let span = index..<index + said.count
                guard span.map(spelled) == said,
                    span.dropFirst().allSatisfy({
                        text[words[$0 - 1].upperBound..<words[$0].lowerBound].elementsEqual(" ")
                    }),
                    span.upperBound == words.count || spelled(span.upperBound) != "of"
                else { continue }
                return (words[index].lowerBound..<words[span.upperBound - 1].upperBound, mark)
            }
        }
        return nil
    }

    /// "slash" after a domain, as in "example.com slash pricing": the path joined on, "example.com/pricing".
    static func pathsJoined(_ text: [Character]) -> [Character] {
        var text = text
        var at = 0
        while at < text.count {
            let words = Words.ranges(in: text)
            guard
                let index = words.indices.first(where: { index in
                    index > 0 && index + 1 < words.count && words[index].lowerBound >= at
                        && String(text[words[index]]).lowercased() == "slash"
                        && text[words[index - 1].upperBound..<words[index].lowerBound].elementsEqual(" ")
                        && text[words[index].upperBound..<words[index + 1].lowerBound].elementsEqual(" ")
                        && isAddress(text, before: words[index - 1].upperBound)
                })
            else { break }
            text.replaceSubrange(words[index - 1].upperBound..<words[index + 1].lowerBound, with: ["/"])
            at = words[index - 1].upperBound + 1
        }
        return text
    }

    /// Whether the text ending at `end` ends with a domain or a path on one: letters, a dot and letters, no spaces.
    private static func isAddress(_ text: [Character], before end: Int) -> Bool {
        var start = end
        while start > 0, text[start - 1] != " " { start -= 1 }
        let token = text[start..<end]
        guard let dot = token.lastIndex(of: "."), dot > start, dot + 1 < end else { return false }
        return text[dot - 1].isLetter && text[dot + 1].isLetter
    }
}
