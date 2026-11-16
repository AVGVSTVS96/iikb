/// An address you speak, written as one: "John dot Smith at Gmail dot com." becomes "john.smith@gmail.com", and
/// "w w w dot example dot com slash pricing" "www.example.com/pricing". The words for the signs an address has (at, dot,
/// underscore, dash, hyphen, slash, colon) become them, number words and spoken digit runs become digits ("twenty
/// one", "one two three", "oh" beside digits as 0), the spaces go, and so does the closing period. It is the same
/// spoken form Apple's, Gboard's and NVIDIA NeMo's dictation read, and nothing is listed per person. Only the first
/// "at" is the sign, since an address has one. Each language says its signs, digits and endings in its own words
/// ("juan punto perez arroba gmail punto com", `SpokenForms`).
enum SpokenAddress {
    private enum Piece: Equatable {
        case symbol(String)
        case number(String)
        case word(String)
    }

    /// What `said` spells as an address, or nil when it says nothing.
    static func read(_ said: String, _ spoken: SpokenForms = .english) -> String? {
        var text = ""
        var at = false
        for piece in pieces(said, spoken) {
            switch piece {
            case .symbol(let sign) where at && spoken.signs[sign] == "@": text += sign
            case .symbol(let sign):
                at = at || spoken.signs[sign] == "@"
                text += spoken.signs[sign]!
            case .number(let digits): text += digits
            case .word(let word): text += word
            }
        }
        return text.isEmpty ? nil : text
    }

    /// What `said` spells when all of it is a web address or an email's domain, as in a search field: an address has no
    /// two plain words in a row ("how to reach example dot com" is a question about one).
    static func domain(_ said: String, _ spoken: SpokenForms = .english) -> String? {
        let pieces = pieces(said, spoken)
        let plain = pieces.map { piece -> Bool in
            if case .word(let word) = piece { return word.count > 1 }
            return false
        }
        guard !zip(plain, plain.dropFirst()).contains(where: { $0 && $1 }), let address = read(said, spoken) else {
            return nil
        }
        return address.wholeMatch(of: /(https?:\/\/)?([a-z0-9_.+-]+@)?([a-z0-9-]+\.)+[a-z]{2,}(\/\S*)?/) == nil
            ? nil : address
    }

    /// The digits `said` says: number words, digit runs and the digits in what the model wrote ("555-1234"), and nothing
    /// else but a "+" it starts with ("plus one ...") and, in a field that takes one (`point`), the first decimal point,
    /// said or written; nil when there are no digits. A letter O beside a digit is 0 here, where only digits go.
    static func digits(_ said: String, point: Bool = false, _ spoken: SpokenForms = .english) -> String? {
        var digits = ""
        var pointed = !point
        for piece in pieces(said, spoken, zeros: spoken.zeros.union(["o"])) {
            switch piece {
            case .number(let number): digits += number
            case .word("plus") where digits.isEmpty: digits = "+"
            case .word("point") where !pointed && !digits.isEmpty:
                digits += "."
                pointed = true
            case .word(let word):
                for character in word {
                    if character.isNumber {
                        digits.append(character)
                    } else if character == "+", digits.isEmpty {
                        digits = "+"
                    } else if character == ".", !pointed, digits.last?.isNumber == true {
                        digits += "."
                        pointed = true
                    }
                }
            case .symbol: break
            }
        }
        while let last = digits.last, !last.isNumber { digits.removeLast() }
        return digits.isEmpty ? nil : digits
    }

    /// `text` with an address spoken inside it written as one (`emails`, then `webAddresses`).
    static func inline(_ text: String, lexicon: Lexicon? = nil, _ spoken: SpokenForms = .english) -> String {
        webAddresses(emails(text, lexicon: lexicon, spoken), spoken)
    }

    /// `text` with an email address spoken inside it written as one, found by its domain: after an "at", a domain with
    /// its ending, spoken ("email me at john at gmail dot com" is "email me at john@gmail.com") or written, when the name
    /// before the "at" has a dot, underscore, dash or digit in it ("jane.doe at gmail.com") or is one word that's a name
    /// ("send it to Renner at fastmail.com") whose domain no other "at" follows ("reach Caspian at caspian.work at
    /// proton.me"), since "shop at example.com" is a sentence. Text that isn't one is returned as it is.
    private static func emails(_ text: String, lexicon: Lexicon?, _ spoken: SpokenForms) -> String {
        let ats = spoken.words(for: "@")
        guard ats.contains(where: { text.contains(" \($0) ") }) else { return text }
        var words = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        var from = 0
        while let at = words[from...].firstIndex(where: { ats.contains(clean($0)) }) {
            from = at + 1
            guard let host = host(in: words, after: at, spoken), let local = local(in: words, before: at, spoken) else {
                continue
            }
            guard words[local..<at].map({ $0.lowercased() }) != ["one"],
                let name = read(words[local..<at].joined(separator: " "), spoken)
            else { continue }
            guard
                host.spoken || name.contains(where: { "._-".contains($0) || $0.isNumber })
                    || named(words, local, before: at, lexicon: lexicon)
                        && !(host.end < words.count && ats.contains(clean(words[host.end])))
            else { continue }
            let address = name + "@" + host.name
            words.replaceSubrange(local..<host.end, with: [address + host.tail])
            from = local + 1
        }
        return words.joined(separator: " ")
    }

    /// `text` with a web address spoken in it written as one, found by its ending ("open Kestrel dot run" is "open
    /// kestrel.run"), though never at or after "the" or "my" ("the dot com bubble", "at the park dot com is down").
    private static func webAddresses(_ text: String, _ spoken: SpokenForms) -> String {
        let dots = spoken.words(for: ".")
        guard
            dots.contains(where: {
                text.contains(" \($0) ") || text.contains(" \($0.prefix(1).uppercased() + $0.dropFirst()) ")
            })
        else { return text }
        var words = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        var at = 0
        while at < words.count {
            if !spoken.determiners.contains(clean(words[at])),
                at == 0 || !spoken.determiners.contains(clean(words[at - 1])),
                let host = host(in: words, after: at - 1, spoken), host.spoken
            {
                words.replaceSubrange(at..<host.end, with: [host.name + host.tail])
            }
            at += 1
        }
        return words.joined(separator: " ")
    }

    /// Whether `text` goes on with " at " and an address's domain ("at fastmail.com", "at proton dot me").
    static func startsHost(_ text: String) -> Bool {
        let words = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        return words.count > 2 && words[0].isEmpty && clean(words[1]) == "at"
            && host(in: words, after: 1, .english) != nil
    }

    /// Whether the name before an "at" is one word, not starting its sentence, written as a name or one the lexicon
    /// lacks ("send it to Renner at fastmail.com", "tamsin at", but not "Shop at example.com" or "I work at fastmail.com").
    private static func named(_ words: [String], _ local: Int, before at: Int, lexicon: Lexicon?) -> Bool {
        let word = words[local]
        guard local + 1 == at, local > 0, !".!?".contains(words[local - 1].last ?? "."), word.count > 1,
            word.allSatisfy(\.isLetter)
        else { return false }
        return word.first!.isUppercase && word.dropFirst().allSatisfy { !$0.isUppercase }
            || lexicon.map { !$0.isWord(word.lowercased()) } == true
    }

    private static func host(in words: [String], after at: Int, _ forms: SpokenForms) -> (
        name: String, end: Int, tail: String, spoken: Bool
    )? {
        let dots = forms.words(for: ".")
        var name = ""
        var end = at + 1
        var tail = ""
        var spoken = false
        var last = ""
        while end < words.count {
            let label = words[end].prefix { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." }.dropLast {
                $0 == "."
            }
            guard !label.isEmpty else { break }
            name += label.lowercased()
            last = String(label.split(separator: ".").last ?? label)
            tail = String(words[end].dropFirst(label.count))
            end += 1
            guard tail.isEmpty, end + 1 < words.count, dots.contains(clean(words[end])) else { break }
            name += "."
            spoken = true
            end += 1
        }
        let labels = name.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count > 1, labels.allSatisfy({ !$0.isEmpty }),
            forms.isEnding(last, next: tail.isEmpty && end < words.count ? words[end] : nil)
        else { return nil }
        return (name, end, tail, spoken)
    }

    /// Where the name before an "at" starts: the plain word beside it, and what's spoken as part of one before that, or
    /// the name before digits said after it ("tamsin one oh one at").
    private static func local(in words: [String], before at: Int, _ spoken: SpokenForms) -> Int? {
        let joiners = spoken.words(for: ".").union(spoken.words(for: "_")).union(spoken.words(for: "-"))
        let zeros = spoken.zeros.union(["o"])
        var start = at
        var digits = 0
        while start > 0 {
            let word = words[start - 1]
            guard word.allSatisfy({ $0.isLetter || $0.isNumber || "_-.".contains($0) }) else { break }
            let first = pieces(word, spoken).first
            let number =
                first.map { if case .number = $0 { true } else { false } } == true
                || start < at && zeros.contains(word.lowercased())
            let spelled =
                number || word.count == 1 && (spoken.lettersJoin || spelledOn(words, start, before: at, joiners))
            let joins = joiners.contains(word.lowercased()) || start < at && joiners.contains(words[start].lowercased())
            guard start == at || spelled || joins || digits == at - start && digits >= 2 else { break }
            start -= 1
            if number, digits == at - start - 1 { digits += 1 }
        }
        return start < at ? start : nil
    }

    /// Whether the word after `index` goes on spelling a name: the "at" itself, a letter or digit alone, or a joiner
    /// ("j o h n", "j punto smith"), so a lone "a" before a name ("escríbeme a ventas arroba") stays a word.
    private static func spelledOn(_ words: [String], _ index: Int, before at: Int, _ joiners: Set<String>) -> Bool {
        let next = words[index]
        return index == at || next.count == 1 || next.allSatisfy(\.isNumber) || joiners.contains(next.lowercased())
    }

    private static func pieces(_ said: String, _ spoken: SpokenForms, zeros: Set<String>? = nil) -> [Piece] {
        let zeros = zeros ?? spoken.zeros
        let cleaned = said.split(whereSeparator: \.isWhitespace).map { joinedLetters(clean(String($0))) }
        var tokens: [Piece] = []
        var values: [Int?] = []
        var index = 0
        while index < cleaned.count {
            let pair = index + 1 < cleaned.count ? cleaned[index] + " " + cleaned[index + 1] : ""
            if spoken.signs[pair] != nil {
                tokens.append(.symbol(pair))
                values.append(nil)
                index += 2
                continue
            }
            let parts = cleaned[index].split(separator: "-").map(String.init)
            for word in parts.count > 1 && parts.allSatisfy({ spoken.numbers[$0] != nil }) ? parts : [cleaned[index]]
            where !word.isEmpty {
                let number = spoken.numbers[word]
                tokens.append(
                    spoken.signs[word] != nil
                        ? .symbol(word)
                        : number.map { .number(String($0)) }
                            ?? (word.allSatisfy(\.isNumber) ? .number(word) : .word(word)))
                values.append(number)
            }
            index += 1
        }
        var pieces: [Piece] = []
        var at = 0
        while at < tokens.count {
            if let tens = values[at], at + 1 < tokens.count, let unit = values[at + 1],
                let number = Spoken.joined(tens, unit)
            {
                pieces.append(.number(String(number)))
                at += 2
            } else {
                pieces.append(tokens[at])
                at += 1
            }
        }
        for order in [Array(pieces.indices), pieces.indices.reversed()] {
            for at in order {
                guard case .word(let word) = pieces[at], zeros.contains(word) else { continue }
                let neighbours = [at - 1, at + 1].filter { pieces.indices.contains($0) }
                if neighbours.contains(where: { if case .number = pieces[$0] { true } else { false } }) {
                    pieces[at] = .number("0")
                }
            }
        }
        return pieces
    }

    /// "peter" for "p-e-t-e-r", as the model writes letters you spell: a dash between two letters that each stand alone.
    private static func joinedLetters(_ token: String) -> String {
        let characters = Array(token)
        let alone = { (at: Int) in
            at < 0 || at >= characters.count || !characters[at].isLetter && !characters[at].isNumber
        }
        return String(
            characters.enumerated().filter { at, character in
                let spelled =
                    character == "-" && at > 0 && at + 1 < characters.count && characters[at - 1].isLetter
                    && characters[at + 1].isLetter
                return !(spelled && alone(at - 2) && alone(at + 2))
            }.map(\.element))
    }

    private static func clean(_ token: String) -> String {
        String(token.lowercased().drop { "\"'(".contains($0) }.reversed().drop { ".,;!?\")".contains($0) }.reversed())
    }
}
