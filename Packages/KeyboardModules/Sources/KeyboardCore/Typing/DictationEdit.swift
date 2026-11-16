/// A language model's reply to a dictation, read as an edit of what was said and never as text of its own: the model
/// may leave words out and set the marks, the capitals and the lines. The reply's words are lined up with the words
/// heard, as many as line up in order (`Token`), and between two that do:
/// - words only heard were left out ("um", a word said twice, what "I mean" takes back, a list's "one" and "two");
/// - words the reply has in their place stand when they spell what was heard ("chat GPT" as "ChatGPT", "four thirty"
///   as "4:30", "pm" as "p.m.") or were each said elsewhere, as a correction's are ("add Daniel, actually make it
///   Danielle"); otherwise the words heard go back, between the reply's marks ("going to" back to "gonna");
/// - words the reply adds where none were said stand only as said elsewhere; otherwise there is no edit (`init?` is
///   nil) and the dictation is typed without the model, as for an answer, a preamble or a digit it made up.
/// A list ends its sentence: items with more of their sentence said after them ("pick up milk, eggs and bread on the
/// way home") are no list, so there is no edit either.
/// A word said elsewhere counts once for each time it was said and not lined up or reworded, so a reply can't say
/// anything twice that was said once. No edit holds a word or a number that wasn't said, and nothing else in iikb takes a model's
/// text (`DictationWriting.written`).
struct DictationEdit {
    struct Line {
        /// What opened the line in the reply: "- ", "* " or "• ", or "1. " or "1) ". A marker is layout, not a word, so
        /// the number said for it ("first", "two") is left out, and never goes back with a word beside it.
        enum Marker { case bullet, number }

        var marker: Marker?
        /// The line without its marker, empty for the blank line between paragraphs.
        var text: [Character]
        /// The stretch of what was heard the line stands for, from where the line before's ends: what a list goes
        /// back to with Lists off.
        var said: Range<Int>
    }

    /// A word or a number as an edit compares them: a word lowercased without apostrophes or accents, and a number as
    /// its digits however it's said or written, with a point for its decimal point or colon, so the model may write it
    /// its own way: "sixty thousand" and "$60,000" are 60000, "third" and "3rd" 3th, "five five five" and "555" 555,
    /// "3.30" and "3:30" 3.30.
    struct Token {
        var key: String
        var range: Range<Int>
        var isNumber = false
        /// Three digits or more said one by one ("two oh six, five five five"), which a reply may group its own way.
        var digitByDigit = false
    }

    /// The most words heard in a row an edit leaves out: it takes back a phrase, never a sentence. On real dictations
    /// (scripts/voiceloop) a reply that left out more had mostly dropped something meant.
    static let leftOutAtMost = 7

    let heard: [Character]
    var lines: [Line]

    init?(of heard: [Character], as reply: [Character]) {
        let read = Self.lines(of: reply)
        let said = Self.tokens(in: heard)
        let reply = Array(read.map(\.text).joined(separator: "\n"))
        let written = Self.tokens(in: reply)
        guard !written.isEmpty, Self.marks(reply, outside: written, typed: Set(heard), said: said) else { return nil }
        var opensItem: Set<Int> = []
        var lineStart = 0
        for line in read {
            if line.marker != nil, let first = written.firstIndex(where: { $0.range.lowerBound >= lineStart }),
                written[first].range.lowerBound < lineStart + line.text.count
            {
                opensItem.insert(first)
            }
            lineStart += line.text.count + 1
        }
        guard
            let (body, stands, _) = Self.lined(said, written).compactMap({
                Self.edit(heard, said, as: reply, written, lined: $0, opensItem: opensItem)
            }).min(by: { $0.putBack < $1.putBack })
        else { return nil }

        let texts = body.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        var lines: [Line] = []
        var start = 0
        var from = 0
        var next = 0
        for (index, line) in read.enumerated() {
            let end = start + line.text.count
            var last: Int?
            while next < written.count, written[next].range.lowerBound < end {
                if let stood = stands[next] { last = max(last ?? stood, stood) }
                next += 1
            }
            let to = last.map { max(from, Self.closed(said[$0].range.upperBound, in: heard)) } ?? from
            lines.append(Line(marker: line.marker, text: Array(texts[index]), said: from..<to))
            from = to
            start = end + 1
        }
        for (index, item) in lines.enumerated() where item.marker != nil && !item.said.isEmpty {
            guard let next = lines[(index + 1)...].first(where: { !$0.text.isEmpty }), next.marker == nil else {
                continue
            }
            let ends = heard[..<item.said.upperBound].last { !Self.closers.contains($0) && !$0.isWhitespace }
            guard let ends, TypingEngine.sentenceEnders.contains(ends) else { return nil }
        }
        self.heard = heard
        self.lines = lines
    }

    /// The edit as text, its lists as `lists` has them, marked and introduced as `SpokenList` writes a list said, so
    /// the style's commas and words apply to it as to any dictation. `prose` is the style's sentence marks
    /// (`DictationStyle.punctuated`), for each run of lines that aren't items, since an item is no sentence: it loses
    /// its closing period and gets none back.
    /// - numbered: "1. " and up for each run of items the reply numbered, counted here, and "• " for the rest.
    /// - bulleted: "• " for every item.
    /// - off: each run of items goes back to the stretch of what was heard it stands for, on the line before it.
    func written(lists: DictationLists, prose: ([Character]) -> [Character]) -> [Character] {
        let lines = lists == .off ? unlisted() : self.lines
        var out: [[Character]] = []
        var at = 0
        while at < lines.count {
            var end = at
            if lines[at].marker == nil {
                while end < lines.count, lines[end].marker == nil { end += 1 }
                var paragraph = lines[at..<end].map(\.text)
                if at > 0 { paragraph = Array(paragraph.drop(while: \.isEmpty)) }
                if end < lines.count { while paragraph.last?.isEmpty == true { paragraph.removeLast() } }
                if !paragraph.isEmpty {
                    let text = prose(Array(paragraph.joined(separator: "\n")))
                    out.append(end < lines.count ? SpokenList.intro(text) : text)
                }
            } else {
                var number = 0
                while end < lines.count, let marker = lines[end].marker {
                    number = end > at && lines[end - 1].marker == .number ? number + 1 : 1
                    let numbered = lists == .numbered && marker == .number
                    out.append(SpokenList.marker(numbered ? number : nil) + Self.item(lines[end].text))
                    end += 1
                }
            }
            at = end
        }
        return Array(out.joined(separator: "\n"))
    }

    /// The lines with each run of items put back as the stretch of what was heard it stands for, on the line before.
    private func unlisted() -> [Line] {
        var out: [Line] = []
        var at = 0
        while at < lines.count {
            guard lines[at].marker != nil else {
                out.append(lines[at])
                at += 1
                continue
            }
            var end = at
            while end < lines.count, lines[end].marker != nil { end += 1 }
            let said = lines[at].said.lowerBound..<lines[end - 1].said.upperBound
            var text = Array(heard[said].drop { $0.isWhitespace || ",.;:".contains($0) })
            while text.last?.isWhitespace == true { text.removeLast() }
            if text.isEmpty { text = Array(lines[at..<end].map(\.text).joined(separator: ", ")) }
            while out.last?.text.isEmpty == true { out.removeLast() }
            if let last = out.indices.last {
                out[last].text += [" "] + text
            } else {
                out.append(Line(marker: nil, text: text, said: said))
            }
            at = end
        }
        return out
    }

    /// An item's text without the period that would end it as a sentence.
    private static func item(_ text: [Character]) -> [Character] {
        var text = text
        if text.last == ".", text.dropLast().last != ".", !Words.closesAbbreviation(text, at: text.count - 1) {
            text.removeLast()
        }
        return text
    }

    /// The reply's lines without the spaces around them or the blank lines it starts and ends with, each with its
    /// marker taken off. A number of up to two digits marks an item, so "2027. was" stays a sentence.
    private static func lines(of reply: [Character]) -> [(marker: Line.Marker?, text: [Character])] {
        var reply = reply.drop(while: \.isWhitespace)
        while reply.last?.isWhitespace == true { reply.removeLast() }
        return reply.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map { line in
            var text = Array(line.drop(while: \.isWhitespace))
            while text.last?.isWhitespace == true { text.removeLast() }
            let digits = text.prefix { $0.isASCII && $0.isNumber }.count
            if text.count > 2, "-*•".contains(text[0]), text[1] == " " {
                return (.bullet, Array(text.dropFirst(2).drop(while: \.isWhitespace)))
            }
            if (1...2).contains(digits), digits + 2 < text.count, ".)".contains(text[digits]), text[digits + 1] == " " {
                return (.number, Array(text.dropFirst(digits + 2).drop(while: \.isWhitespace)))
            }
            return (nil, text)
        }
    }

    /// The words that say a sign a reply may write against a number, which stands only where one of them was said.
    private static let signs: [Character: Set<String>] = [
        "$": ["dollar", "dollars", "bucks"], "%": ["percent"], "€": ["euro", "euros"], "£": ["pound", "pounds"],
        "¢": ["cent", "cents"],
    ]

    /// Whether every character of the reply is one the transcript has, or shows and is no markup: none holds a format
    /// or invisible code point, a word's letters included, and outside the words, numbers and emoji each is a mark a
    /// person types in a message. That's spaces, punctuation and a money or percent sign whose word was said (`signs`),
    /// and none of markup's: an asterisk or a backslash, an underscore against a word's edge, a "#" opening a line, or
    /// a symbol such as a backtick.
    private static func marks(
        _ reply: [Character], outside words: [Token], typed heard: Set<Character>, said: [Token]
    ) -> Bool {
        var inWord = Array(repeating: false, count: reply.count)
        for word in words { for at in word.range { inWord[at] = true } }
        return reply.indices.allSatisfy { at in
            let character = reply[at]
            guard !heard.contains(character) else { return true }
            let invisible = character.unicodeScalars.contains {
                switch $0.properties.generalCategory {
                case .format, .privateUse, .unassigned, .surrogate: true
                case .control: !$0.properties.isWhitespace
                default: $0.properties.isDefaultIgnorableCodePoint
                }
            }
            if invisible { return false }
            if inWord[at] || character.isWhitespace { return true }
            if let names = signs[character] { return said.contains { names.contains($0.key) } }
            if character.isCurrencySymbol { return false }
            switch character {
            case "*", "\\": return false
            case "#": return at > 0 && !reply[at - 1].isNewline
            case "_":
                return (at > 0 && Words.isWordCharacter(reply[at - 1]))
                    == (at + 1 < reply.count && Words.isWordCharacter(reply[at + 1]))
            default: return character.isPunctuation
            }
        }
    }

    /// The reply's text with each rewording that doesn't stand undone, which heard word each written one stands for,
    /// and how many words heard went back; nil when the reply adds a word, says one twice or keeps none.
    private static func edit(
        _ heard: [Character], _ said: [Token], as reply: [Character], _ written: [Token], lined pairs: [(Int, Int)],
        opensItem: Set<Int>
    ) -> (body: [Character], stands: [Int?], putBack: Int)? {
        var body = reply
        var free = Array(repeating: true, count: said.count)
        var typed = Array(repeating: false, count: said.count)
        for (i, _) in pairs { (free[i], typed[i]) = (false, true) }
        var runs: [Range<Int>] = []
        for start in said.indices where said[start].isNumber {
            let end = said[start...].prefix(while: \.isNumber).endIndex
            if end - start >= 2 { runs += (start + 2...end).map { start..<$0 } }
        }
        func spends(_ words: ArraySlice<Token>, after place: Int) -> Bool {
            var left = free
            for word in words {
                if let at = (place..<said.count).first(where: { left[$0] && spells(said[$0], as: word) }) {
                    left[at] = false
                } else if word.isNumber,
                    let run = runs.first(where: {
                        $0.lowerBound >= place && $0.allSatisfy { left[$0] } && spells(said[$0], as: [word])
                    })
                {
                    for at in run { left[at] = false }
                } else {
                    return false
                }
            }
            for at in said.indices where free[at] && !left[at] { typed[at] = true }
            free = left
            return true
        }

        var stands: [Int?] = Array(repeating: nil, count: written.count)
        for (i, j) in pairs { stands[j] = i }
        var undone: [(range: Range<Int>, with: [Character])] = []
        var putBack = 0
        var keeps = !pairs.isEmpty
        var (i, j) = (0, 0)
        for (nextHeard, nextWritten) in pairs + [(said.count, written.count)] {
            defer { (i, j) = (nextHeard + 1, nextWritten + 1) }
            let words = written[j..<nextWritten]
            guard !words.isEmpty else { continue }
            guard i < nextHeard else {
                guard spends(words, after: nextHeard) else { return nil }
                keeps = true
                continue
            }
            for index in words.indices { stands[index] = nextHeard - 1 }
            let spelled = spells(said[i..<nextHeard], as: words)
            let spent = !spelled && spends(words, after: i)
            guard spent || (i..<nextHeard).allSatisfy({ free[$0] }) else { return nil }
            for at in i..<nextHeard {
                free[at] = false
                if !spent { typed[at] = true }
            }
            keeps = keeps || spelled || spent
            if spelled || spent { continue }
            guard words.count <= nextHeard - i + 1 else { return nil }
            let stretch = words.first!.range.lowerBound..<words.last!.range.upperBound
            let range = signed(stretch, in: body)
            guard !body[range].contains(where: \.isNewline), !glued(stretch, in: body) else { return nil }
            var (first, last) = (i, nextHeard - 1)
            if opensItem.contains(j) { while first < last, said[first].isNumber { first += 1 } }
            if opensItem.contains(nextWritten) { while last > first, said[last].isNumber { last -= 1 } }
            var with = heard[signed(said[first].range.lowerBound..<said[last].range.upperBound, in: heard)]
                .map { $0.isNewline ? " " : $0 }
            if body[range.lowerBound].isUppercase, with[0].isLowercase { with[0] = Character(with[0].uppercased()) }
            undone.append((range, with))
            putBack += last - first + 1
        }
        var leftOut = 0
        for at in said.indices {
            leftOut = typed[at] ? 0 : leftOut + 1
            if leftOut > leftOutAtMost { return nil }
        }
        guard keeps else { return nil }
        for (range, with) in undone.reversed() { body.replaceSubrange(range, with: with) }
        return (body, stands, putBack)
    }

    /// The pairs of tokens heard and written that line up, as many as line up in order, two ways: a word heard more
    /// than once lined up with the last time it was said, as what's said over is said again after it, and with the
    /// first, leaving the later times for a correction to bring forward.
    private static func lined(_ said: [Token], _ written: [Token]) -> [[(Int, Int)]] {
        let width = written.count + 1
        var longest = [Int](repeating: 0, count: (said.count + 1) * width)
        for i in said.indices.reversed() {
            for j in written.indices.reversed() {
                longest[i * width + j] =
                    spells(said[i], as: written[j])
                    ? longest[(i + 1) * width + j + 1] + 1
                    : max(longest[(i + 1) * width + j], longest[i * width + j + 1])
            }
        }
        return [true, false].map { last in
            var pairs: [(Int, Int)] = []
            var (i, j) = (0, 0)
            while i < said.count, j < written.count {
                let here = longest[i * width + j]
                if last, longest[(i + 1) * width + j] == here {
                    i += 1
                } else if spells(said[i], as: written[j]) {
                    pairs.append((i, j))
                    i += 1
                    j += 1
                } else if longest[i * width + j + 1] == here {
                    j += 1
                } else {
                    i += 1
                }
            }
            return pairs
        }
    }

    /// `range` with the signs stuck to its ends, as "$" is to "$60,000" and "%" to "50%", but not a mark around it
    /// or a sign between it and another word.
    private static func signed(_ range: Range<Int>, in text: [Character]) -> Range<Int> {
        var start = range.lowerBound
        while start > 0, isSign(text[start - 1]) { start -= 1 }
        if start > 0, Words.isWordCharacter(text[start - 1]) { start = range.lowerBound }
        var end = range.upperBound
        while end < text.count, isSign(text[end]) { end += 1 }
        if end < text.count, Words.isWordCharacter(text[end]) { end = range.upperBound }
        return start..<end
    }

    /// Whether only signs stand between `range` and a word beside it, as "/" does in "1/2": the two are written as one
    /// thing, so the words said can't go back for a part of it.
    private static func glued(_ range: Range<Int>, in text: [Character]) -> Bool {
        var start = range.lowerBound
        while start > 0, isSign(text[start - 1]) { start -= 1 }
        var end = range.upperBound
        while end < text.count, isSign(text[end]) { end += 1 }
        return start > 0 && Words.isWordCharacter(text[start - 1])
            || end < text.count && Words.isWordCharacter(text[end])
    }

    private static func isSign(_ character: Character) -> Bool {
        !Words.isWordCharacter(character) && !character.isWhitespace && !Words.openers.contains(character)
            && !closers.contains(character) && !",.;:!?…".contains(character)
    }

    /// Whether `written` spells what's `said` (`Token.key`): the same letters, digits and signs, with a point or colon
    /// wherever one was said ("3.30" as "3:30", never "4.5" as "45"). The only one it may add is a time's colon, as
    /// Parakeet runs "nine forty-five" into "945", never a decimal point ("fifteen hundred" is never "15.00"). Its
    /// numbers start and end where the ones said do, so two said apart are never one ("three thousand, two hundred" is
    /// never 3,000,200, nor "3, 4" 34) and one is never two, but for digits said one by one and a time's or a year's
    /// halves ("four thirty", "twenty twenty-six").
    private static func spells(_ said: some Collection<Token>, as written: some Collection<Token>) -> Bool {
        let (heard, reply) = (spelled(said), spelled(written))
        return heard.text == reply.text && heard.marks.isSubset(of: reply.marks)
            && reply.marks.subtracting(heard.marks).isSubset(of: reply.times)
            && heard.edges.symmetricDifference(reply.edges).isSubset(of: heard.loose)
    }

    private static func spells(_ said: Token, as written: Token) -> Bool {
        said.key == written.key || written.isNumber && spells([said], as: [written])
    }

    /// `tokens`' keys run together without their points and colons, where each of those stood in that, and which of
    /// them is a time's colon, between an hour and its two digits of minutes ("7:30", "19:05"). `edges` is where its
    /// numbers start and end in that, and `loose` the edges another spelling may lack or add: any inside digits said
    /// one by one, and the one between a number of one or two digits and the two digits after it.
    private static func spelled(_ tokens: some Collection<Token>) -> (
        text: [Character], marks: Set<Int>, times: Set<Int>, edges: Set<Int>, loose: Set<Int>
    ) {
        var spelled: (text: [Character], marks: Set<Int>, times: Set<Int>, edges: Set<Int>, loose: Set<Int>) = (
            [], [], [], [], []
        )
        var before: Token?
        for token in tokens {
            let start = spelled.text.count
            defer {
                if token.isNumber {
                    spelled.edges.formUnion([start, spelled.text.count])
                    if token.digitByDigit { spelled.loose.formUnion(start + 1..<spelled.text.count) }
                    if let before, before.isNumber, (1...2).contains(before.key.count), token.key.count == 2,
                        (before.key + token.key).allSatisfy({ $0.isASCII && $0.isNumber })
                    {
                        spelled.loose.insert(start)
                    }
                }
                before = token
            }
            let parts = token.key.split(separator: ":", omittingEmptySubsequences: false)
            let time =
                parts.count == 2 && (1...2).contains(parts[0].count) && parts[1].count == 2
                && Int(parts[0]).map { $0 < 24 } == true && Int(parts[1]).map { $0 < 60 } == true
            for character in token.key {
                if character == "." || character == ":" {
                    spelled.marks.insert(spelled.text.count)
                    if time { spelled.times.insert(spelled.text.count) }
                } else {
                    spelled.text.append(character)
                }
            }
        }
        return spelled
    }

    /// Where the marks that close what ends at `end` end: a sentence's, a bracket's, a quote's.
    private static func closed(_ end: Int, in text: [Character]) -> Int {
        var end = end
        while end < text.count, TypingEngine.sentenceEnders.contains(text[end]) || closers.contains(text[end]) {
            end += 1
        }
        return end
    }

    private static let closers: Set<Character> = [")", "]", "}", "\"", "”", "'", "’", "»", "›"]

    /// The words, numbers and emoji in `text`, split at marks, spaces, hyphens and where letters meet digits. A
    /// number's key is its digits with its decimal points and colons, and the sign written against it ("-5"); any
    /// other character that's a number ("½", "３") is one of its own.
    static func tokens(in text: [Character]) -> [Token] {
        func isDigit(_ character: Character) -> Bool { character.isASCII && character.isNumber }
        func isSign(_ at: Int) -> Bool {
            (text[at] == "-" || text[at].isMathSymbol) && at + 1 < text.count && isDigit(text[at + 1])
                && (at == 0 || !Words.isWordCharacter(text[at - 1]))
        }
        func groups(_ at: Int) -> Bool {
            text[at] == "," && at + 3 < text.count && (1...3).allSatisfy { isDigit(text[at + $0]) }
                && (at + 4 == text.count || !isDigit(text[at + 4]))
        }
        var pieces: [Token] = []
        var at = 0
        while at < text.count {
            let start = at
            if isDigit(text[at]) || isSign(at) {
                var digits = isSign(at) ? String(text[at]) : ""
                if isSign(at) { at += 1 }
                while at < text.count,
                    isDigit(text[at]) || ".:".contains(text[at]) && at + 1 < text.count && isDigit(text[at + 1])
                        || groups(at)
                {
                    if text[at] != "," { digits.append(text[at]) }
                    at += 1
                }
                if at + 2 <= text.count, ["st", "nd", "rd", "th"].contains(String(text[at..<at + 2]).lowercased()),
                    at + 2 == text.count || !text[at + 2].isLetter
                {
                    digits += "th"
                    at += 2
                }
                pieces.append(Token(key: digits, range: start..<at, isNumber: true))
            } else if text[at].isLetter {
                var letters = ""
                while at < text.count,
                    text[at].isLetter
                        || Words.apostrophes.contains(text[at]) && at + 1 < text.count && text[at + 1].isLetter
                {
                    if text[at].isLetter { letters += plain(text[at]) }
                    at += 1
                }
                pieces.append(Token(key: letters, range: start..<at))
            } else if text[at].isNumber {
                pieces.append(Token(key: String(text[at]), range: at..<at + 1, isNumber: true))
                at += 1
            } else {
                if text[at].unicodeScalars.contains(where: { $0.properties.isEmojiPresentation || $0 == "\u{FE0F}" }) {
                    pieces.append(Token(key: String(text[at]), range: at..<at + 1))
                }
                at += 1
            }
        }
        return numbered(pieces, in: text)
    }

    /// `words` with each number said in them one token, read as `Spoken` reads it ("sixty thousand" 60000, "twenty
    /// first" 21th), and three digits or more said one by one as one ("four one five, oh one" 41501). Two stay two
    /// numbers, as "3, 4 people" are.
    private static func numbered(_ words: [Token], in text: [Character]) -> [Token] {
        func apart(_ first: Token, _ second: Token, by marks: String) -> Bool {
            let between = text[first.range.upperBound..<second.range.lowerBound]
            return !between.isEmpty && between.allSatisfy(marks.contains)
        }
        func run(from start: Int) -> [String] {
            var end = start + 1
            while end < words.count, !words[end].isNumber, apart(words[end - 1], words[end], by: " -") { end += 1 }
            return words[start..<end].map(\.key)
        }
        var tokens: [Token] = []
        var oneByOne: [Token] = []
        func endRun() {
            if oneByOne.count >= 3 {
                tokens.append(
                    Token(
                        key: oneByOne.map(\.key).joined(),
                        range: oneByOne[0].range.lowerBound..<oneByOne[oneByOne.count - 1].range.upperBound,
                        isNumber: true, digitByDigit: true))
            } else {
                tokens += oneByOne
            }
            oneByOne = []
        }
        var digits = false
        var at = 0
        while at < words.count {
            var token = words[at]
            var end = at + 1
            var digit = false
            if !token.isNumber, Spoken.value(of: token.key) != nil, case let said = run(from: at),
                let (value, used) = Spoken.cardinal(said, at: 0)
            {
                token.key = String(value)
                end = at + used
                if used < said.count, let ordinal = Spoken.ordinal(of: said[used]),
                    let whole = Spoken.joined(value, ordinal)
                {
                    token.key = "\(whole)th"
                    end += 1
                } else {
                    digit = used == 1 && value < 10
                }
                token.isNumber = true
                token.range = token.range.lowerBound..<words[end - 1].range.upperBound
            } else if !token.isNumber, let ordinal = Spoken.ordinal(of: token.key) {
                token.key = "\(ordinal)th"
                token.isNumber = true
            } else if digits, token.key == "oh",
                let zero = SpokenNumber.spoken(token.key, first: false, next: words.dropFirst(end).first?.key)
            {
                token.key = zero
                token.isNumber = true
                digit = true
            } else if token.isNumber, token.key.count == 1, token.key.allSatisfy({ $0.isASCII && $0.isNumber }) {
                digit = true
            }
            if let last = oneByOne.last, !digit || !apart(last, token, by: " ,-") { endRun() }
            if digit { oneByOne.append(token) } else { tokens.append(token) }
            digits = digit
            at = end
        }
        endRun()
        return tokens
    }

    /// A letter lowercased, and a Latin one without its accent: "Á" is "a", "ø" is "o".
    private static func plain(_ letter: Character) -> String {
        let lower = letter.lowercased()
        guard !letter.isASCII, let first = lower.unicodeScalars.first else { return lower }
        let latin = "LATIN SMALL LETTER "
        guard let name = first.properties.name, name.hasPrefix(latin) else { return String(first) }
        let base = name.dropFirst(latin.count).prefix { $0 != " " }
        return base.count == 1 ? base.lowercased() : String(first)
    }
}

extension DictationEditing {
    /// Whether a language model edits it where one is on the iPhone (`DictationEdit`): the app asks it to know whether
    /// to fetch and run one, and `DictationWriting.written` to know whether to take its reply, so the two can't differ.
    public var asksModel: Bool { self == .clean }
}
