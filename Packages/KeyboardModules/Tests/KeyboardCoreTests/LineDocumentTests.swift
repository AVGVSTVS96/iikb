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

    @Test func aSelectionIsWhatTheNextEditReplaces() {
        let line = LineDocument("see you at noon")
        line.select(11..<15)
        #expect(line.selectedText == "noon")
        #expect(line.textBeforeInput == "see you at ")
        #expect(line.textAfterInput == "")
        #expect(line.caret == 11)
        line.insert("six")
        #expect(line.text == "see you at six")
        #expect(line.selection == 14..<14)
        line.select(4..<8)
        line.deleteBackward(1)
        #expect(line.text == "see at six")
        #expect(line.selection == 4..<4)
        line.select(4..<7)
        line.deleteBackward(2)
        #expect(line.text == "seesix", "the selection counts as one of the deletes")
    }

    @Test func movingCollapsesTheSelectionFromTheEndItLeaves() {
        let line = LineDocument("one two three")
        line.select(4..<7)
        line.moveCursor(by: -1)
        #expect(line.selection == 3..<3)
        line.select(4..<7)
        line.moveCursor(by: 1)
        #expect(line.selection == 8..<8)
        line.select(4..<7)
        line.moveCursor(by: 0)
        #expect(line.selection == 7..<7)
    }

    @Test func aSelectionStaysInsideTheText() {
        let line = LineDocument("hi")
        line.select(-3..<9)
        #expect(line.selection == 0..<2)
        line.placeCaret(at: 40)
        #expect(line.selection == 2..<2)
    }

    @Test func theEngineTypesOverASelection() {
        var engine = TypingEngine(traits: InputTraits(returnKind: .send, returnRequiresText: true))
        let line = LineDocument()
        engine.documentChanged(line)
        engine.type("meet at five ", in: line)
        line.select(8..<12)
        engine.documentChanged(line)
        #expect(engine.text.selected == "five")
        engine.type("six", in: line)
        #expect(line.text == "Meet at six ")
        #expect(line.selection == 11..<11)
        #expect(engine.text.before == "Meet at six")
        #expect(engine.text.selected.isEmpty)
    }

    @Test func theEngineDeletesASelectionWithOneDelete() {
        var engine = TypingEngine(traits: InputTraits(returnKind: .send, returnRequiresText: true))
        let line = LineDocument()
        engine.documentChanged(line)
        engine.type("call me later", in: line)
        line.select(5..<8)
        engine.documentChanged(line)
        engine.perform(.delete, in: line)
        #expect(line.text == "Call later")
        #expect(engine.text.before == "Call ")
        engine.perform(.delete, in: line)
        #expect(line.text == "Calllater")
        #expect(engine.documentChanged(line) == .current)
    }

    @Test func returnSendsAllOfTheLineEvenWithAWordSelected() {
        let line = LineDocument("Can you check the build")
        line.select(0..<3)
        line.insert("\n")
        #expect(
            line.takeReturned() == "Can you check the build",
            "send sends the message, as Messages' does, not what typing over the word would leave")
        #expect(line.text.isEmpty)
        #expect(line.selection == 0..<0)
    }
}
