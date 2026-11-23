import Testing

@testable import KeyboardCore

struct PasteOfferTests {
    private func engine(_ text: String = "") -> (TypingEngine, TestDocument) {
        var engine = TypingEngine()
        engine.corrector = Corrector(source: testLexicon)
        let document = TestDocument(text)
        engine.documentChanged(document)
        engine.copied = Copied(text: "see you at 6")
        return (engine, document)
    }

    @Test func anEmptyFieldOffersWhatWasJustCopied() {
        let (engine, _) = engine()
        #expect(engine.pasteOffer == Copied(text: "see you at 6"))
    }

    @Test func aFieldWithTextOffersNothing() {
        let (engine, _) = engine("hi")
        #expect(engine.pasteOffer == nil)
    }

    @Test func typingGivesWayToSuggestionsAndTheCopyIsntOfferedAgain() {
        var (engine, document) = engine()
        engine.perform(.character("h"), in: document)
        #expect(engine.pasteOffer == nil)
        engine.perform(.delete, in: document)
        #expect(document.text.isEmpty)
        #expect(engine.pasteOffer == nil)
    }

    @Test func pastingTakesTheOffer() {
        var (engine, document) = engine()
        engine.handle(.paste("see you at 6"), in: document)
        #expect(document.text == "see you at 6")
        engine.documentChanged(TestDocument())
        #expect(engine.pasteOffer == nil)
    }

    @Test func anOpenPanelOffersNothing() {
        var (engine, document) = engine()
        engine.handle(.panel(.clipboard), in: document)
        #expect(engine.pasteOffer == nil)
    }
}
