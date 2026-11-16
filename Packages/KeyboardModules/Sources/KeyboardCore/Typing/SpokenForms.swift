/// How a language says what a dictation writes as signs: punctuation said by name ("comma", "virgule"), its fillers
/// ("um", "euh"), an address's words ("at", "arroba") and its digits, and how it sets its marks: French's space before
/// "?", "!", ":" and ";", and Spanish's "¿" and "¡". One per language (`Language.spoken`).
struct SpokenForms: Sendable {
    /// A mark said by name, lowercase and spelled as written ("deux-points", "punto y coma").
    struct Mark {
        let name: String
        let words: Int
        let mark: String
        /// Whether it ends a sentence and is also an everyday word ("punto", "Punkt", "a capo"), which
        /// `Prose.articles` keeps a word unless it ends what's said. A colon or a new line goes on with lowercase
        /// words, so "dos puntos" and "nueva línea" aren't.
        let noun: Bool
    }

    /// Where a mark's name stays a word.
    enum Prose {
        /// After one of `after` ("the grace period") or before one of `before` ("a period of time"): English's, as its
        /// dictation has always read it.
        case listed(after: Set<String>, before: Set<String>)
        /// Between two numbers ("drei Komma fünf"), right after one of these articles while the sentence goes on ("ein
        /// Komma fehlt"), and, for a name that's also a noun, unless it ends what's said: last, before a mark, a capital
        /// or another name ("certo punto ho", "punto Por favor"), never before a comma ("un buen punto, lo vemos"), with no
        /// article right before it ("ein Punkt") and not said twice ("punto por punto").
        case articles(Set<String>)
    }

    /// Its marks said by name, longest first, so "punto y coma" is ";" before "punto" is ".".
    let marks: [Mark]
    let prose: Prose
    /// Its "um" and "uh", each drawn-out letter once ("ähm" for "ähhhm").
    let fillers: Set<String>
    /// Words that point at what follows, so it's a thing named and not an address: "the dot com bubble".
    let determiners: Set<String>
    /// An address's signs said by name, lowercase, a word or two ("guion bajo").
    let signs: [String: String]
    /// The endings a web address said in words ends with. Where one is also a word ("com" in Portuguese, "se" in
    /// Swedish), it's an ending only written lowercase with no lowercase word after it (`isEnding`).
    let domains: Set<String>
    /// Its number words: zero to nine, and in English the teens and tens too.
    let numbers: [String: Int]
    /// Words for 0 inside a run of digits ("oh").
    let zeros: Set<String>
    /// Words that ask for a code or number said after them ("the code is"), so four digits said one by one are one.
    let cues: Set<String>
    /// Whether a letter alone before an address's name is part of it, as English's is where the model splits a name
    /// ("t in 101 at"); where a letter alone is a word ("a", "y", "e", "o", "i", "å") only a spelled run is.
    let lettersJoin: Bool
    /// Marks a no-break space comes before, as French writes "Merci !".
    let spaced: Set<Character>
    /// The marks a sentence opens with for the mark it ends with, as Spanish writes "¿Vienes?".
    let opened: [Character: Character]

    init(
        marks: [String: String], nouns: Set<String> = [], prose: Prose, fillers: Set<String>,
        determiners: Set<String>? = nil, signs: [String: String], domains: Set<String>, numbers: [String: Int],
        zeros: Set<String> = [], cues: Set<String>, lettersJoin: Bool = false, spaced: Set<Character> = [],
        opened: [Character: Character] = [:]
    ) {
        self.marks = marks.map {
            Mark(name: $0, words: Words.ranges(in: Array($0)).count, mark: $1, noun: nouns.contains($0))
        }
        .sorted { ($0.words, $0.name.count, $0.name) > ($1.words, $1.name.count, $1.name) }
        self.prose = prose
        self.fillers = fillers
        if let determiners {
            self.determiners = determiners
        } else if case .articles(let articles) = prose {
            self.determiners = articles
        } else {
            self.determiners = []
        }
        self.signs = signs
        self.domains = domains
        self.numbers = numbers
        self.zeros = zeros
        self.cues = cues
        self.lettersJoin = lettersJoin
        self.spaced = spaced
        self.opened = opened
    }

    /// Whether `word`, with `next` after it, ends a web address said in words: one of `domains`, and in a language
    /// other than English, written lowercase with no lowercase word after it, since "Com certeza" and "se här" are prose.
    func isEnding(_ word: String, next: String?) -> Bool {
        guard domains.contains(word.lowercased()) else { return false }
        guard case .articles = prose else { return true }
        return word == word.lowercased() && !(next?.first?.isLowercase ?? false)
    }

    /// The single words said for `sign`.
    func words(for sign: String) -> Set<String> {
        Set(signs.filter { $0.value == sign && !$0.key.contains(" ") }.keys)
    }

    /// The digit a word says, "zero" to "nine".
    func digit(_ word: String) -> Int? {
        numbers[word].flatMap { $0 < 10 ? $0 : nil }
    }

    /// `text` with its marks set as the language sets them (`spaced`, `opened`).
    func typeset(_ text: [Character]) -> [Character] {
        opening(spacing(text))
    }

    /// A no-break space before each run of spaced marks after a word that ends there, in place of the space the model
    /// wrote or where it wrote none, though never inside "14:30", "https://" or ":)".
    private func spacing(_ text: [Character]) -> [Character] {
        guard !spaced.isEmpty else { return text }
        let spaces: Set<Character> = [" ", "\u{A0}", "\u{202F}"]
        var text = text
        var at = text.count - 1
        while at > 0 {
            defer { at -= 1 }
            guard spaced.contains(text[at]), !spaced.contains(text[at - 1]) else { continue }
            var end = at + 1
            while end < text.count, spaced.contains(text[end]) { end += 1 }
            guard end == text.count || text[end].isWhitespace || "»\"”".contains(text[end]) else { continue }
            var start = at
            while start > 0, spaces.contains(text[start - 1]) { start -= 1 }
            guard start > 0, !text[start - 1].isNewline else { continue }
            text.replaceSubrange(start..<at, with: ["\u{A0}"])
            at = start + 1
        }
        return text
    }

    /// Each sentence ended with a mark that has an opening one, opened with it where the model didn't.
    private func opening(_ text: [Character]) -> [Character] {
        guard !opened.isEmpty else { return text }
        var text = text
        for sentence in DictationStyle.sentences(in: text).reversed() {
            guard let mark = sentence.mark else { continue }
            var start = sentence.range.lowerBound
            while start < mark, text[start] == "•" || text[start] == " " || Words.openers.contains(text[start]) {
                start += 1
            }
            var end = mark
            var opens: [Character] = []
            while end >= start, TypingEngine.sentenceEnders.contains(text[end]) {
                if let open = opened[text[end]], !opens.contains(open) { opens.insert(open, at: 0) }
                end -= 1
            }
            let said = text[sentence.range]
            opens.removeAll { said.contains($0) }
            if !opens.isEmpty, start < mark { text.insert(contentsOf: opens, at: start) }
        }
        return text
    }
}

extension Language {
    /// How it's said (`SpokenForms`).
    var spoken: SpokenForms { SpokenForms.all[self] ?? .english }
}

extension SpokenForms {
    static let all: [Language: SpokenForms] = [
        .english: .english, .spanish: .spanish, .french: .french, .german: .german, .portuguese: .portuguese,
        .italian: .italian, .swedish: .swedish,
    ]

    /// An address's signs said in English, which other languages say too, though never "colon", a word in most of them.
    private static let englishSigns = [
        "at": "@", "dot": ".", "underscore": "_", "dash": "-", "hyphen": "-", "slash": "/",
    ]

    static let english = SpokenForms(
        marks: [
            "new paragraph": "\n\n", "new line": "\n", "newline": "\n", "question mark": "?", "exclamation point": "!",
            "exclamation mark": "!", "full stop": ".", "period": ".", "comma": ",", "semicolon": ";", "colon": ":",
        ],
        prose: .listed(
            after: [
                "a", "an", "the", "this", "that", "each", "every", "per", "my", "your", "his", "her", "our", "their",
                "its", "no", "any", "some", "one", "grace", "trial", "waiting", "time", "oxford", "serial", "same",
                "which", "what",
            ], before: ["of"]),
        fillers: ["um", "uh", "uhm", "erm", "hm"], determiners: Spoken.determiners,
        signs: englishSigns.merging(["colon": ":"]) { $1 },
        domains: [
            "com", "org", "net", "edu", "gov", "io", "co", "us", "uk", "ai", "app", "dev", "me", "info", "tv", "ca",
            "de", "fr", "run",
        ],
        numbers: Spoken.numbers, zeros: ["oh"],
        cues: ["code", "pin", "number", "passcode", "password", "extension", "zip", "id", "digits", "otp"],
        lettersJoin: true)

    static let spanish = SpokenForms(
        marks: [
            "punto": ".", "punto final": ".", "punto y seguido": ".", "punto y aparte": "\n\n", "coma": ",",
            "punto y coma": ";", "dos puntos": ":", "signo de interrogación": "?", "signo de exclamación": "!",
            "signo de admiración": "!", "nueva línea": "\n", "nuevo párrafo": "\n\n",
        ],
        nouns: ["punto", "punto final"],
        prose: .articles([
            "el", "la", "los", "las", "un", "una", "unos", "unas", "este", "esta", "estos", "estas", "ese", "esa",
            "esos", "esas", "aquel", "aquella", "mi", "mis", "tu", "tus", "su", "sus", "nuestro", "nuestra",
        ]),
        fillers: ["eh", "em", "ehm"],
        signs: englishSigns.merging([
            "arroba": "@", "punto": ".", "guion": "-", "guión": "-", "guion bajo": "_", "guión bajo": "_", "barra": "/",
        ]) { $1 },
        domains: [
            "com", "org", "net", "edu", "gov", "io", "co", "uk", "ai", "app", "dev", "info", "tv", "es", "mx", "ar",
            "cl",
        ],
        numbers: [
            "cero": 0, "uno": 1, "dos": 2, "tres": 3, "cuatro": 4, "cinco": 5, "seis": 6, "siete": 7, "ocho": 8,
            "nueve": 9,
        ],
        cues: ["código", "clave", "contraseña", "número", "pin"], opened: ["?": "¿", "!": "¡"])

    static let french = SpokenForms(
        marks: [
            "point": ".", "point final": ".", "virgule": ",", "point-virgule": ";", "point virgule": ";",
            "deux-points": ":", "deux points": ":", "point d'interrogation": "?", "point d'exclamation": "!",
            "à la ligne": "\n", "retour à la ligne": "\n", "nouvelle ligne": "\n", "point à la ligne": ".\n",
            "nouveau paragraphe": "\n\n",
        ],
        nouns: ["point", "point final"],
        prose: .articles([
            "le", "la", "les", "un", "une", "ce", "cet", "cette", "ces", "mon", "ma", "mes", "ton", "ta", "tes", "son",
            "sa", "ses", "notre", "votre", "nos", "vos", "leur", "leurs",
        ]),
        fillers: ["euh", "heu", "hum", "hm"],
        signs: englishSigns.merging([
            "arobase": "@", "arobas": "@", "point": ".", "tiret": "-", "trait d'union": "-", "tiret bas": "_",
            "barre": "/",
        ]) { $1 },
        domains: ["com", "org", "net", "edu", "gov", "io", "co", "uk", "app", "dev", "info", "tv", "fr", "be", "ch"],
        numbers: [
            "zéro": 0, "un": 1, "deux": 2, "trois": 3, "quatre": 4, "cinq": 5, "six": 6, "sept": 7, "huit": 8,
            "neuf": 9,
        ],
        cues: ["code", "numéro", "pin"], spaced: ["?", "!", ":", ";"])

    static let german = SpokenForms(
        marks: [
            "punkt": ".", "komma": ",", "fragezeichen": "?", "ausrufezeichen": "!", "doppelpunkt": ":",
            "semikolon": ";", "strichpunkt": ";", "neue zeile": "\n", "zeilenumbruch": "\n", "neuer absatz": "\n\n",
        ],
        nouns: ["punkt"],
        prose: .articles([
            "der", "die", "das", "den", "dem", "des", "ein", "eine", "einen", "einem", "einer", "eines", "kein",
            "keine", "keinen", "dieser", "diese", "dieses", "diesen", "mein", "meine", "dein", "deine", "sein",
            "seine", "ihr", "ihre", "unser", "unsere",
        ]),
        fillers: ["äh", "ähm", "äm", "öh", "öhm", "ehm", "hm"],
        signs: englishSigns.merging([
            "ät": "@", "punkt": ".", "unterstrich": "_", "bindestrich": "-", "strich": "-", "schrägstrich": "/",
        ]) { $1 },
        domains: [
            "com", "org", "net", "edu", "gov", "io", "co", "uk", "ai", "app", "dev", "info", "tv", "de", "at", "ch",
        ],
        numbers: [
            "null": 0, "eins": 1, "zwei": 2, "zwo": 2, "drei": 3, "vier": 4, "fünf": 5, "sechs": 6, "sieben": 7,
            "acht": 8, "neun": 9,
        ],
        cues: ["code", "nummer", "pin", "passwort", "kennwort"])

    static let portuguese = SpokenForms(
        marks: [
            "ponto": ".", "ponto final": ".", "vírgula": ",", "ponto e vírgula": ";", "dois pontos": ":",
            "ponto de interrogação": "?", "ponto de exclamação": "!", "nova linha": "\n", "novo parágrafo": "\n\n",
            "ponto parágrafo": "\n\n",
        ],
        nouns: ["ponto", "ponto final"],
        prose: .articles([
            "o", "a", "os", "as", "um", "uma", "uns", "umas", "este", "esta", "esse", "essa", "aquele", "aquela", "meu",
            "minha", "teu", "tua", "seu", "sua", "nosso", "nossa",
        ]),
        fillers: ["hã", "ãh", "ahn", "hum", "hm"],
        signs: englishSigns.merging([
            "arroba": "@", "ponto": ".", "hífen": "-", "traço": "-", "underline": "_", "sublinhado": "_", "barra": "/",
        ]) { $1 },
        domains: ["com", "org", "net", "edu", "gov", "io", "co", "uk", "ai", "app", "dev", "info", "tv", "br", "pt"],
        numbers: [
            "zero": 0, "um": 1, "uma": 1, "dois": 2, "duas": 2, "três": 3, "quatro": 4, "cinco": 5, "seis": 6,
            "meia": 6, "sete": 7, "oito": 8, "nove": 9,
        ],
        cues: ["código", "número", "senha", "pin"])

    static let italian = SpokenForms(
        marks: [
            "punto": ".", "punto fermo": ".", "virgola": ",", "punto e virgola": ";", "due punti": ":",
            "punto interrogativo": "?", "punto di domanda": "?", "punto esclamativo": "!", "a capo": "\n",
            "punto a capo": ".\n", "punto e a capo": ".\n", "nuova riga": "\n", "nuovo paragrafo": "\n\n",
        ],
        nouns: ["punto", "punto fermo", "a capo"],
        prose: .articles([
            "il", "lo", "la", "i", "gli", "le", "un", "uno", "una", "questo", "questa", "quel", "quello", "quella",
            "mio", "mia", "tuo", "tua", "suo", "sua", "nostro", "nostra", "vostro", "vostra",
        ]),
        fillers: ["eh", "em", "ehm", "uhm", "hm", "mh"],
        signs: englishSigns.merging([
            "chiocciola": "@", "punto": ".", "trattino": "-", "trattino basso": "_", "barra": "/",
        ]) { $1 },
        domains: ["com", "org", "net", "edu", "gov", "co", "uk", "app", "dev", "info", "tv", "it"],
        numbers: [
            "zero": 0, "uno": 1, "due": 2, "tre": 3, "quattro": 4, "cinque": 5, "sei": 6, "sette": 7, "otto": 8,
            "nove": 9,
        ],
        cues: ["codice", "numero", "pin", "password"])

    static let swedish = SpokenForms(
        marks: [
            "punkt": ".", "kommatecken": ",", "komma tecken": ",", "frågetecken": "?", "utropstecken": "!",
            "kolon": ":", "semikolon": ";", "ny rad": "\n", "nytt stycke": "\n\n",
        ],
        nouns: ["punkt"],
        prose: .articles([
            "en", "ett", "den", "det", "de", "denna", "detta", "dessa", "min", "mitt", "mina", "din", "ditt", "dina",
            "sin", "sitt", "vår", "vårt", "er", "ert",
        ]),
        fillers: ["eh", "äh", "öh", "öhm", "ehm", "hm"],
        signs: englishSigns.merging([
            "snabel-a": "@", "snabela": "@", "snabel a": "@", "punkt": ".", "understreck": "_", "bindestreck": "-",
            "snedstreck": "/",
        ]) { $1 },
        domains: ["com", "org", "net", "edu", "gov", "io", "co", "uk", "ai", "app", "dev", "info", "tv", "se"],
        numbers: [
            "noll": 0, "ett": 1, "två": 2, "tre": 3, "fyra": 4, "fem": 5, "sex": 6, "sju": 7, "åtta": 8, "nio": 9,
        ],
        cues: ["kod", "koden", "nummer", "pin", "lösenord"])
}
