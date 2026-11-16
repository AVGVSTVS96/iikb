/// Punctuation said by name, as every dictation does: "Hi Sam comma thanks period" is "Hi Sam, thanks.", and "new
/// line" and "new paragraph" break the line, each in the words of the language said (`SpokenForms`). A name stays a word
/// where it's one (`SpokenForms.Prose`), or before an address's ending when it's also the address's dot ("gmail punto
/// com"). Parakeet's own marks around a name give way to it, as does the same mark it wrote right before it ("Adresse?
/// Fragezeichen"), while marks said one after another all stay ("punto nueva línea"), and a sentence it ends starts with
/// a capital.
enum SaidMarks {
    static func written(_ text: [Character], _ spoken: SpokenForms = .english) -> [Character] {
        var text = pathsJoined(text, spoken)
        var searched = 0
        while let (range, mark) = said(in: text, from: searched, spoken) {
            var start = range.lowerBound
            var end = range.upperBound
            while start > 0, text[start - 1] == " " || start > searched && ",.".contains(text[start - 1]) { start -= 1 }
            if start > searched, String(text[start - 1]) == mark { start -= 1 }
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

    private static func said(in text: [Character], from: Int, _ spoken: SpokenForms) -> (Range<Int>, String)? {
        let words = Words.ranges(in: text)
        for index in words.indices where words[index].lowerBound >= from && index > 0 {
            guard let said = name(in: text, words, at: index, spoken) else { continue }
            guard isMark(said, in: text, words, at: index, spoken) else { continue }
            return (words[index].lowerBound..<words[index + said.words - 1].upperBound, said.mark)
        }
        return nil
    }

    /// The longest mark named from word `index` on.
    private static func name(in text: [Character], _ words: [Range<Int>], at index: Int, _ spoken: SpokenForms)
        -> SpokenForms.Mark?
    {
        spoken.marks.first { said in
            index + said.words <= words.count
                && Words.plain(String(text[words[index].lowerBound..<words[index + said.words - 1].upperBound]))
                    .lowercased() == said.name
        }
    }

    private static func isMark(
        _ said: SpokenForms.Mark, in text: [Character], _ words: [Range<Int>], at index: Int, _ spoken: SpokenForms
    ) -> Bool {
        let spelled = { (index: Int) in Words.plain(String(text[words[index]]).lowercased()) }
        let next = index + said.words
        if spoken.signs[said.name] == ".", next < words.count,
            spoken.isEnding(
                String(text[words[next]]), next: next + 1 < words.count ? String(text[words[next + 1]]) : nil)
        {
            return false
        }
        switch spoken.prose {
        case .listed(let after, let before):
            return !after.contains(spelled(index - 1)) && (next == words.count || !before.contains(spelled(next)))
        case .articles(let articles):
            let number = { (index: Int) in
                text[words[index]].contains(where: \.isNumber) || spoken.numbers[spelled(index)] != nil
            }
            if next < words.count, number(index - 1), number(next) { return false }
            let ends =
                next == words.count
                || text[words[next - 1].upperBound..<words[next].lowerBound].contains { $0 != " " && $0 != "," }
                || text[words[next].lowerBound].isUppercase || name(in: text, words, at: next, spoken) != nil
            let article = articles.contains(spelled(index - 1))
            let twice = index >= 2 && spelled(index - 2) == spelled(index)
            return said.noun ? ends && !article && !twice : ends || !article
        }
    }

    /// "slash" after a domain, as in "example.com slash pricing": the path joined on, "example.com/pricing".
    static func pathsJoined(_ text: [Character], _ spoken: SpokenForms = .english) -> [Character] {
        let slashes = spoken.words(for: "/")
        var text = text
        var at = 0
        while at < text.count {
            let words = Words.ranges(in: text)
            guard
                let index = words.indices.first(where: { index in
                    index > 0 && index + 1 < words.count && words[index].lowerBound >= at
                        && slashes.contains(String(text[words[index]]).lowercased())
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
