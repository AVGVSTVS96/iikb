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

    /// Writes the rewrite of what it acts on in its place, the caret after it, moving the caret to the end of the text
    /// after it first when it acts on that too.
    mutating func rewrite(_ rewrite: Rewrite, in document: some TextDocument) {
        attach(document)
        let last = lastRewrite
        let target = rewriting
        let (written, plain) = rewrite.apply(to: target, plain: last?.plain ?? TextStyle.plain(target))
        guard written != target else { return }
        if text.selected.isEmpty, last == nil, let after = text.after, !after.isEmpty {
            moveCaret(by: after.count, in: document)
        }
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
