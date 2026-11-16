import Testing

@testable import KeyboardCore

struct SnippetTests {
    let address = Snippet(name: "Address", text: "1 Infinite Loop", keyword: "!addr")
    let log = Snippet(name: "Log", text: "console.log({cursor})", keyword: "!log")
    let greet = Snippet(
        name: "Greeting", text: "Hi {argument name=\"Name\"}, see you in {argument name=“City” default=“Paris”}.",
        keyword: "!hi")

    func engine(_ expansion: SnippetExpansion = .immediately, snippets: [Snippet]? = nil) -> TypingEngine {
        var engine = TypingEngine()
        engine.settings.autoCapitalization = false
        engine.settings.autoCorrection = false
        engine.settings.snippetExpansion = expansion
        engine.snippets = snippets ?? [address, log, greet]
        return engine
    }

    @Test func aTemplateReadsRaycastsPlaceholders() {
        let template = Template(
            "Hi {argument name=\"Name\"}, {cursor}in {argument name=“City” default=“Paris”}, {argument name=\"Name\"} {x}"
        )
        #expect(template.arguments == [.init(name: "Name"), .init(name: "City", defaultValue: "Paris")])
        let filled = template.filled(["Ana"])
        #expect(filled.text == "Hi Ana, in Paris, Ana {x}", "a name shares its value; an empty one takes its default")
        #expect(filled.cursor == 8)
        let unnamed = Template("{argument} and {argument}")
        #expect(unnamed.arguments.map(\.name) == ["Argument 1", "Argument 2"], "each unnamed argument is its own")
        #expect(Template("{ argument }").arguments.map(\.name) == ["Argument"])
        #expect(Template("{arguments}").filled().text == "{arguments}")
        #expect(Template("a {b").filled().text == "a {b")
    }

    @Test func aLinksValuesArePercentEncoded() {
        #expect(Template.percentEncoded("café & co/2") == "caf%C3%A9%20%26%20co%2F2")
    }

    @Test func aKeywordTypedAtAWordsStartBecomesItsSnippet() {
        var engine = engine()
        let document = TestDocument()
        engine.type("my place: !addr", in: document)
        #expect(document.text == "my place: 1 Infinite Loop")
        engine.type(" ok", in: document)
        #expect(document.text == "my place: 1 Infinite Loop ok")
    }

    @Test func aKeywordInsideAWordStaysAsTyped() {
        var engine = engine()
        let document = TestDocument()
        engine.type("wow!addr", in: document)
        #expect(document.text == "wow!addr")
    }

    @Test func onlyAKeywordTheKeyboardTypedExpands() {
        var engine = engine()
        let document = TestDocument("!add")
        engine.documentChanged(document)
        engine.type("r", in: document)
        #expect(document.text == "!addr", "the keyboard typed only its last letter")
    }

    @Test func aKeywordMatchesWhateverItsCase() {
        var engine = engine(snippets: [Snippet(name: "Sig", text: "Bassim", keyword: "sig")])
        engine.settings.autoCapitalization = true
        let document = TestDocument()
        engine.type("sig", in: document)
        #expect(document.text == "Bassim", "auto-capitalization typed Sig")
    }

    @Test func afterDelimiterWaitsForASpaceOrPunctuationAndKeepsIt() {
        var engine = engine(.afterDelimiter)
        let document = TestDocument()
        engine.type("!addr", in: document)
        #expect(document.text == "!addr")
        engine.perform(.space, in: document)
        #expect(document.text == "1 Infinite Loop ")
        engine.type("!addr", in: document)
        engine.perform(.character("."), in: document)
        #expect(document.text == "1 Infinite Loop 1 Infinite Loop.")
        engine.type(" !addr", in: document)
        engine.perform(.return, in: document)
        #expect(document.text == "1 Infinite Loop 1 Infinite Loop. 1 Infinite Loop\n")
    }

    @Test func offExpandsNothing() {
        var engine = engine(.off)
        let document = TestDocument()
        engine.type("!addr ", in: document)
        #expect(document.text == "!addr ")
    }

    @Test func cursorPutsTheCaretInTheSnippet() {
        var engine = engine(.afterDelimiter)
        let document = TestDocument()
        engine.type("!log ", in: document)
        #expect(document.text == "console.log() ")
        engine.type("x", in: document)
        #expect(document.text == "console.log(x) ")
    }

    @Test func argumentsAreAskedForBeforeTheSnippetGoesIn() {
        var engine = engine(.afterDelimiter)
        let document = TestDocument("so ")
        engine.documentChanged(document)
        engine.type("!hi ", in: document)
        #expect(engine.panel == .form)
        #expect(engine.fill?.fields.map(\.name) == ["Name", "City"])
        #expect(document.text == "so !hi", "the keyword waits, the space with it")
        engine.type("ana", in: document)
        #expect(engine.query == "ana")
        #expect(engine.faces(on: .phone).returnKind == .next)
        engine.perform(.return, in: document)
        #expect(engine.fill?.at == 1)
        #expect(engine.faces(on: .phone).returnKind == .go)
        engine.type("Rome", in: document)
        engine.deleteWord(in: document)
        #expect(engine.fill?.values == ["ana", ""], "holding delete empties the field's value too")
        engine.perform(.delete, in: document)
        #expect(document.text == "so !hi", "delete in an empty field leaves the app alone")
        engine.perform(.return, in: document)
        #expect(engine.panel == nil)
        #expect(document.text == "so Hi ana, see you in Paris. ")
    }

    @Test func backLeavesTheKeywordAsTyped() {
        var engine = engine(.afterDelimiter)
        let document = TestDocument()
        engine.type("!hi ", in: document)
        engine.type("x", in: document)
        engine.handle(.panel(nil), in: document)
        #expect(engine.panel == nil)
        #expect(document.text == "!hi ")
    }

    @Test func theBarOffersKeywordsAfterThePrefix() {
        var engine = engine(.afterDelimiter)
        engine.settings.predictiveText = false
        let document = TestDocument("see ")
        engine.documentChanged(document)
        engine.type("!", in: document)
        #expect(engine.suggestions.map(\.text) == ["!hi", "!log", "!addr"])
        #expect(engine.showsSuggestions, "the keywords show with Predictive Text off")
        engine.type("a", in: document)
        #expect(engine.suggestions == [Suggestion("!addr", .snippet)])
        engine.accept(engine.suggestions[0], in: document)
        #expect(document.text == "see 1 Infinite Loop")
    }

    @Test func aSnippetPickedInThePanelGoesInAtTheCaret() {
        var engine = engine()
        let document = TestDocument("at ")
        engine.handle(.panel(.snippets), in: document)
        engine.handle(.snippet(address), in: document)
        #expect(document.text == "at 1 Infinite Loop")
        #expect(engine.panel == .snippets, "the panel stays open for another")
        engine.handle(.snippet(greet), in: document)
        #expect(engine.panel == .form)
        engine.type("bo", in: document)
        engine.handle(.submit, in: document)
        #expect(document.text == "at 1 Infinite LoopHi bo, see you in Paris.")
        #expect(engine.panel == .snippets, "the fill closes back to its panel")
    }

    @Test func aQuicklinksArgumentIsEncodedIntoItsLink() {
        var engine = engine()
        let document = TestDocument()
        let search = Quicklink(name: "Search", link: "https://duckduckgo.com/?q={argument name=\"Query\"}")
        engine.handle(.quicklink(search, opening: false), in: document)
        engine.type("swift ui", in: document)
        engine.perform(.return, in: document)
        #expect(document.text == "https://duckduckgo.com/?q=swift%20ui")
        engine.handle(.quicklink(search, opening: true), in: document)
        engine.type("a&b", in: document)
        engine.perform(.return, in: document)
        #expect(engine.takeFinished() == .open("https://duckduckgo.com/?q=a%26b"))
        #expect(document.text == "https://duckduckgo.com/?q=swift%20ui", "opening types nothing")
    }

    @Test func createSnippetKeepsTheSelectionNamed() {
        var engine = engine()
        let blank = TestDocument(" ")
        engine.documentChanged(blank)
        engine.handle(.createSnippet, in: blank)
        #expect(engine.fill == nil, "with nothing to keep it asks nothing")
        let document = TestDocument("call me at 555 0100 today")
        document.select("555 0100")
        engine.documentChanged(document)
        engine.handle(.createSnippet, in: document)
        #expect(engine.fill?.title == "New Snippet")
        #expect(engine.query == "", "the name's default is its first words")
        engine.perform(.return, in: document)
        #expect(engine.query == "!", "the keyword starts with the prefix")
        engine.type("ADDR", in: document)
        engine.perform(.return, in: document)
        engine.type("work", in: document)
        engine.perform(.return, in: document)
        #expect(engine.takeFinished() == nil, "a keyword another snippet has isn't kept")
        #expect(engine.fill?.at == 1)
        #expect(engine.fill?.problem == "“!addr” is already Address’s keyword.")
        for _ in 0..<4 { engine.perform(.delete, in: document) }
        #expect(engine.fill?.problem == nil, "changing the keyword clears what was wrong")
        engine.type("num", in: document)
        engine.perform(.return, in: document)
        engine.perform(.return, in: document)
        guard case .keep(let snippet) = engine.takeFinished() else {
            Issue.record("nothing kept")
            return
        }
        #expect(
            [snippet.name, snippet.text, snippet.keyword, snippet.tag] == ["555 0100", "555 0100", "!num", "work"])
        #expect(document.text == "call me at 555 0100 today", "the field is left as it was")
    }

    @Test func theSnippetKeyStartsAKeyword() {
        var engine = engine(.afterDelimiter)
        let document = TestDocument()
        engine.type("hi", in: document)
        engine.handle(.trigger(Key(.snippetPrefix("!"))), in: document)
        #expect(document.text == "hi !", "after a word it starts a new one")
        #expect(engine.suggestions.map(\.kind) == [.snippet, .snippet, .snippet])
        engine.type("addr ", in: document)
        #expect(document.text == "hi 1 Infinite Loop ")
        engine.handle(.trigger(Key(.snippetPrefix("!"))), in: document)
        #expect(document.text == "hi 1 Infinite Loop !", "at a word's start it types the prefix alone")
        engine.handle(.panel(.snippets), in: document)
        engine.handle(.trigger(Key(.snippetPrefix("!"))), in: document)
        #expect(engine.query == "!", "in a panel it searches")
    }
}
