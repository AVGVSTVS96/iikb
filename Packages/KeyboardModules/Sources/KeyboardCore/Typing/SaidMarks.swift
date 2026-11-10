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
        var text = text
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
}
