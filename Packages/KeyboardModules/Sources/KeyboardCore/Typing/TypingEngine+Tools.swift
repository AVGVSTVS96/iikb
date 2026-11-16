extension TypingEngine {
    /// What Text Styles and Change Case act on: the selection; else what they last wrote, while the text is as they
    /// left it, so picking one after another changes it again; else all the text the keyboard knows of the field
    /// (docs/design.md, "Text Styles").
    public var rewriting: String {
        if !text.selected.isEmpty { return text.selected }
        return lastRewrite?.text ?? text.before + (text.after ?? "")
    }

    /// What `rewrite` would write in place of `rewriting`, for the panel to show.
    public func preview(_ rewrite: Rewrite) -> String {
        let target = rewriting
        return rewrite.apply(to: target, plain: lastRewrite?.plain ?? TextStyle.plain(target)).text
    }

    private var lastRewrite: Rewritten? {
        guard let rewritten, text.selected.isEmpty, text.owned >= rewritten.text.count,
            text.before.hasSuffix(rewritten.text)
        else { return nil }
        return rewritten
    }

    /// Writes the rewrite of what it acts on in its place, the caret after it. With nothing selected and no rewrite to
    /// change again, that's the whole field, read window by window (`TextDocument.wholeText`); if the reading goes
    /// wrong, nothing is written.
    mutating func rewrite(_ rewrite: Rewrite, in document: some TextDocument) {
        attach(document)
        let last = lastRewrite
        var target = rewriting
        if text.selected.isEmpty, last == nil {
            let whole = document.wholeText()
            documentChanged(document)
            guard let whole, text.after?.isEmpty != false else { return }
            target = whole
        }
        let (written, plain) = rewrite.apply(to: target, plain: last?.plain ?? TextStyle.plain(target))
        guard written != target else { return }
        learnPending()
        forgetWord()
        history.close()
        write(written, replacing: text.selected.isEmpty ? target.count : 0, in: document)
        history.close()
        rewritten = Rewritten(text: written, plain: plain)
        refreshShift()
        suggestionsChanged()
    }

    /// The answer to the calculation the caret ends, for the bar (`Calculation`), unless the caret is inside it.
    var calculation: Suggestion? {
        guard text.after?.first.map({ $0.isWhitespace }) != false else { return nil }
        return Calculation(before: text.before, mark: decimalMark).map {
            Suggestion($0.answer, .answer(replacing: $0.replacing))
        }
    }

    /// What the languages typed put before a number's fraction, unless they differ (`Calculation`).
    private var decimalMark: Character? {
        let marks = Set(settings.languages.map(\.decimalMark))
        return marks.count == 1 ? marks.first : nil
    }

    /// The bar's answer typed in place of its calculation, or after its "=" with a space as it was typed, and a space
    /// after it as after a word. It's typed only while the text still reads as that calculation.
    mutating func accept(answer: String, replacing: String, in document: some TextDocument) {
        guard text.selected.isEmpty,
            let now = Calculation(before: text.before, mark: decimalMark),
            now.answer == answer,
            now.replacing == replacing
        else { return }
        learnPending()
        forgetWord()
        let spaced = replacing.isEmpty && text.before.hasSuffix(" =")
        history.close()
        write((spaced ? " " : "") + answer, replacing: replacing.count, in: document)
        tally.picked += 1
        spaceAfterPick(in: document)
        history.close()
        refreshShift()
        suggestionsChanged()
    }
}

extension TextDocument {
    /// All of the field's text, leaving the caret at its end. A host shows only a window around the caret (300
    /// characters either side in a text view, iOS 27.2 simulator, Nov 16), and may cut it at a line (`TextState`), so
    /// this walks the caret to the start a window at a time, then to the end reading each window after it, checking
    /// each step landed where the text it read says, and stepping one character where a window is empty but the field
    /// goes on. Where a step didn't land, or past 1,000 steps, it puts the caret back and gives nil.
    func wholeText() -> String? {
        var moved = 0
        func move(_ offset: Int) {
            moveCursor(by: offset)
            moved += offset
        }
        func failed() -> String? {
            moveCursor(by: -moved)
            return nil
        }
        var atStart = false
        for _ in 0..<1000 {
            let before = textBeforeInput ?? ""
            let after = textAfterInput
            move(before.isEmpty ? -1 : -before.count)
            if before.isEmpty, textAfterInput == after, textBeforeInput?.isEmpty != false {
                moved += 1
                atStart = true
                break
            }
            guard before.isEmpty || textAfterInput?.hasPrefix(before) == true else { return failed() }
        }
        guard atStart else { return failed() }
        var whole = ""
        for _ in 0..<1000 {
            let after = textAfterInput ?? ""
            let before = textBeforeInput
            move(after.isEmpty ? 1 : after.count)
            if after.isEmpty {
                guard textBeforeInput != before || textAfterInput?.isEmpty == false else {
                    moved -= 1
                    return whole
                }
                whole.append(textBeforeInput?.last ?? "\n")
            } else if textBeforeInput?.hasSuffix(after) == true {
                whole += after
            } else {
                return failed()
            }
        }
        return failed()
    }
}
