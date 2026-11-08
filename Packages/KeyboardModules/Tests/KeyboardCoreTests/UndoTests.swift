import Testing

@testable import KeyboardCore

struct UndoTests {
    private func engine(_ document: TestDocument) -> TypingEngine {
        var engine = TypingEngine()
        engine.settings.autoCapitalization = false
        engine.documentChanged(document)
        return engine
    }

    @Test func undoTakesBackAWordAtATimeAndRedoWritesItAgain() {
        let document = TestDocument()
        var engine = engine(document)
        #expect(!engine.canUndo)
        engine.type("see you there", in: document)
        engine.perform(.undo, in: document)
        #expect(document.text == "see you ")
        engine.perform(.undo, in: document)
        #expect(document.text == "see ")
        #expect(engine.canRedo)
        engine.perform(.redo, in: document)
        #expect(document.text == "see you ")
        engine.perform(.redo, in: document)
        #expect(document.text == "see you there")
        #expect(!engine.canRedo)
    }

    @Test func undoBringsBackWhatDeleteTook() {
        let document = TestDocument("hello world")
        var engine = engine(document)
        for _ in 0..<7 { engine.perform(.delete, in: document) }
        #expect(document.text == "hell")
        engine.perform(.undo, in: document)
        #expect(document.text == "hello world")
    }

    @Test func deletingIntoAWordJustTypedUndoesAsOneStep() {
        let document = TestDocument()
        var engine = engine(document)
        engine.type("cat ", in: document)
        engine.type("dgo", in: document)
        engine.perform(.delete, in: document)
        engine.perform(.delete, in: document)
        engine.type("og", in: document)
        engine.perform(.undo, in: document)
        #expect(document.text == "cat ")
    }

    @Test func aWordTypedAndDeletedLeavesTheWordBeforeItsOwnStep() {
        let document = TestDocument()
        var engine = engine(document)
        engine.type("one ", in: document)
        engine.type("a", in: document)
        engine.perform(.delete, in: document)
        engine.type("two", in: document)
        engine.perform(.undo, in: document)
        #expect(document.text == "one ")
    }

    @Test func typingAfterAnUndoDropsTheRedo() {
        let document = TestDocument()
        var engine = engine(document)
        engine.type("one two", in: document)
        engine.perform(.undo, in: document)
        engine.type("three", in: document)
        #expect(!engine.canRedo)
        #expect(document.text == "one three")
        engine.perform(.undo, in: document)
        #expect(document.text == "one ")
    }

    @Test func anEditTheKeyboardDidntMakeEndsTheHistory() {
        let document = TestDocument()
        var engine = engine(document)
        engine.type("hi there", in: document)
        document.insert(" pasted")
        engine.documentChanged(document)
        #expect(!engine.canUndo)
        engine.perform(.undo, in: document)
        #expect(document.text == "hi there pasted")
    }

    @Test func movingTheCaretEndsTheHistory() {
        let document = TestDocument()
        var engine = engine(document)
        engine.type("hi", in: document)
        engine.handle(.cursor(offset: -1), in: document)
        #expect(!engine.canUndo)
    }

    @Test func anEmojiUndoesOnItsOwn() {
        let document = TestDocument()
        var engine = engine(document)
        engine.type("nice", in: document)
        engine.handle(.emoji("🔥", base: "🔥"), in: document)
        engine.perform(.undo, in: document)
        #expect(document.text == "nice")
    }

    @Test func theKeysDimWithNothingToDo() {
        let document = TestDocument()
        var engine = engine(document)
        let context = { engine.faces(on: .pad) }
        #expect(KeyFace(Key(.undo), trailing: false, context: context()).isDimmed)
        engine.type("a", in: document)
        #expect(!KeyFace(Key(.undo), trailing: false, context: context()).isDimmed)
        #expect(KeyFace(Key(.redo), trailing: false, context: context()).isDimmed)
    }
}
