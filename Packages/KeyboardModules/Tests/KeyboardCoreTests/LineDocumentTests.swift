import Testing

@testable import KeyboardCore

struct LineDocumentTests {
    @Test func returnTakesTheLineAndEmptiesIt() {
        var engine = TypingEngine(traits: InputTraits(returnKind: .send, returnRequiresText: true))
        let line = LineDocument()
        engine.documentChanged(line)
        engine.type("hey hex", in: line)
        #expect(line.text == "Hey hex", "the line capitalizes as a field asking for sentences does")
        engine.perform(.return, in: line)
        #expect(line.takeReturned() == "Hey hex")
        #expect(line.takeReturned() == nil)
        #expect(line.text.isEmpty)
        engine.documentChanged(line)
        #expect(engine.text.isEmpty)
        engine.type("again", in: line)
        #expect(line.text == "Again")
    }

    @Test func theCaretMovesAndEditsWhereItIs() {
        let line = LineDocument("hello world")
        line.moveCursor(by: -6)
        line.deleteBackward(1)
        line.insert("!")
        #expect(line.text == "hell! world")
        #expect(line.textBeforeInput == "hell!")
        #expect(line.textAfterInput == " world")
        line.moveCursor(by: 100)
        #expect(line.caret == line.text.count)
        line.deleteBackward(100)
        #expect(line.text.isEmpty)
    }

    @Test func returnInTheMiddleSendsTheWholeLine() {
        let line = LineDocument("on my way")
        line.moveCursor(by: -4)
        line.insert("\n")
        #expect(line.takeReturned() == "on my way")
    }
}
