import Foundation
import KeyboardStore
import UIKit

/// The space bar trackpad's moves up and down by the lines the app's field really wraps, asked of the field itself
/// through the app's accessibility tree (AXRuntime's `AXElement`, private), the one place a keyboard can learn where a
/// field's lines are (FullKeyboard/AGENTS.md). It answers only where iOS lets the keyboard reach the app's accessibility and
/// the field it finds holds the text the keyboard knows; elsewhere up and down fall back to the engine's. The App Store
/// build (`APP_STORE`) leaves it out.
@MainActor final class FieldLines {
    /// How far the finger travels to move a line: the field's own line height, once the field has answered here.
    private(set) var lineHeight: CGFloat?
    /// Moves the caret by a character offset, as the trackpad's moves sideways do.
    var apply: (Int) -> Void = { _ in }
    private var goal: (x: CGFloat, landing: Int)?
    private var pending = 0
    private var moving = false
    private nonisolated let queue = DispatchQueue(label: "iikb.field-lines")

    #if APP_STORE
        func check(app: String?, before: String) {}
        func move(_ count: Int, before: String) {}
    #else
        /// Asks whether the app's field answers, as the keyboard comes up in it and again as the trackpad starts, since
        /// an empty field has no lines to answer with. Which apps answered is kept once the field holds text.
        func check(app: String?, before: String) {
            goal = nil
            queue.async {
                var height: CGFloat?
                let answer: String
                switch Field.find(matching: before) {
                case .success(let field):
                    let caret = field.rect(field.caret).height
                    height = caret > 0 ? caret : nil
                    answer = height == nil ? "no rects" : "lines"
                case .failure(let stop):
                    answer = stop.rawValue
                }
                if !before.isEmpty { Self.record(app: app, answer: answer) }
                Task { @MainActor in self.lineHeight = height }
            }
        }

        /// Moves the caret `count` lines down, up when negative, keeping its x through a run of moves as a text view
        /// does, through `apply`.
        func move(_ count: Int, before: String) {
            pending += count
            guard !moving else { return }
            moving = true
            let count = pending
            let goal = goal
            pending = 0
            queue.async {
                let move = try? Field.find(matching: before).get().move(count, goal: goal)
                Task { @MainActor in
                    self.moving = false
                    guard let move else {
                        self.lineHeight = nil
                        return
                    }
                    self.goal = move.goal
                    if move.offset != 0 { self.apply(move.offset) }
                }
            }
        }

        /// Keeps, per app, whether its field gave its lines or where asking stopped (`Field.Stop`).
        private nonisolated static func record(app: String?, answer: String) {
            guard let app else { return }
            let url = URL.applicationSupportDirectory.appending(path: "field-access.json")
            let file = StoredFile<[String: String]>(url)
            var seen = file.read().value ?? [:]
            guard seen[app] != answer else { return }
            seen[app] = answer
            file.save(seen)
        }
    #endif
}

#if !APP_STORE
    /// The focused field of the app the keyboard types in, as its accessibility tree describes it: its whole text, the
    /// caret, and where each character sits, in UTF-16 offsets as accessibility counts them.
    nonisolated private struct Field {
        let element: AnyObject
        let text: NSString
        let caret: Int

        /// Where asking the app for its field stopped.
        enum Stop: String, Error {
            case noRuntime = "no runtime"
            case noApp = "no app"
            case noField = "no field"
            case noText = "no text"
            case otherText = "other text"
        }

        /// The field, when its text before the caret ends as `before` does, so it's the field the keyboard types in.
        static func find(matching before: String) -> Result<Field, Stop> {
            guard dlopen("/System/Library/PrivateFrameworks/AXRuntime.framework/AXRuntime", RTLD_NOW) != nil,
                let ax = NSClassFromString("AXElement")
            else { return .failure(.noRuntime) }
            guard let app = call(ax, "primaryApp") else { return .failure(.noApp) }
            guard let element = call(app, "firstResponder") else { return .failure(.noField) }
            guard let text = call(element, "value") as? NSString,
                let caret = range(element, "selectedTextRange")?.location, caret <= text.length
            else { return .failure(.noText) }
            let shown = String(before.suffix(32))
            guard text.substring(to: caret).hasSuffix(shown) else { return .failure(.otherText) }
            return .success(Field(element: element, text: text, caret: caret))
        }

        struct Move {
            var offset: Int
            var goal: (x: CGFloat, landing: Int)
        }

        func move(_ count: Int, goal: (x: CGFloat, landing: Int)?) -> Move? {
            var index = caret
            let x = goal.flatMap { $0.landing == caret ? $0.x : nil } ?? self.x(caret)
            for _ in 0..<abs(count) {
                index = count < 0 ? above(index, x: x) : below(index, x: x)
            }
            let low = min(index, caret)
            let high = max(index, caret)
            let characters = text.substring(with: NSRange(location: low, length: high - low)).count
            return Move(offset: index < caret ? -characters : characters, goal: (x, index))
        }

        /// The caret position on the line above `index`'s nearest `x`, or the text's start from its first line.
        private func above(_ index: Int, x: CGFloat) -> Int {
            let start = first(in: 0...index, onLineOf: index)
            guard start > 0 else { return 0 }
            let previous = first(in: 0...start - 1, onLineOf: start - 1)
            return nearest(x, in: previous...start - 1)
        }

        /// The caret position on the line below `index`'s nearest `x`, or the text's end from its last line.
        private func below(_ index: Int, x: CGFloat) -> Int {
            let end = last(in: index...text.length, onLineOf: index)
            guard end < text.length else { return text.length }
            let next = end + 1
            let nextEnd = last(in: next...text.length, onLineOf: next)
            return nearest(x, in: next...nextEnd)
        }

        /// The first position in `range` on the line `index` is on; positions run in reading order, so it's a bisection.
        private func first(in range: ClosedRange<Int>, onLineOf index: Int) -> Int {
            let line = rect(index)
            var low = range.lowerBound
            var high = range.upperBound
            while low < high {
                let middle = (low + high) / 2
                if sameLine(rect(middle), line) { high = middle } else { low = middle + 1 }
            }
            return low
        }

        private func last(in range: ClosedRange<Int>, onLineOf index: Int) -> Int {
            let line = rect(index)
            var low = range.lowerBound
            var high = range.upperBound
            while low < high {
                let middle = (low + high + 1) / 2
                if sameLine(rect(middle), line) { low = middle } else { high = middle - 1 }
            }
            return low
        }

        private func nearest(_ x: CGFloat, in range: ClosedRange<Int>) -> Int {
            var low = range.lowerBound
            var high = range.upperBound
            while low < high {
                let middle = (low + high) / 2
                if self.x(middle) < x { low = middle + 1 } else { high = middle }
            }
            let snapped = low > range.lowerBound && x - self.x(low - 1) < self.x(low) - x ? low - 1 : low
            return snapped < text.length ? text.rangeOfComposedCharacterSequence(at: snapped).location : snapped
        }

        private func sameLine(_ a: CGRect, _ b: CGRect) -> Bool {
            abs(a.midY - b.midY) < min(a.height, b.height) / 2
        }

        /// Where the caret at `index` sits: at the left of the character after it, or past the last one.
        private func x(_ index: Int) -> CGFloat {
            index < text.length && !isBreak(index) ? rect(index).minX : rect(index).maxX
        }

        /// The rectangle of the character after `index`, or of the one before where there's no character after it on
        /// the line (the text's end, a line break), so it sits on the line the caret at `index` is on.
        func rect(_ index: Int) -> CGRect {
            let at = index < text.length && !isBreak(index) || index == 0 ? index : index - 1
            return bounds(NSRange(location: at, length: at < text.length ? 1 : 0))
        }

        private func isBreak(_ index: Int) -> Bool {
            (text.substring(with: NSRange(location: index, length: 1)) as String).first?.isNewline ?? false
        }

        private func bounds(_ range: NSRange) -> CGRect {
            typealias Bounds = @convention(c) (AnyObject, Selector, NSRange) -> CGRect
            let selector = NSSelectorFromString("boundsForTextRange:")
            guard let method = class_getInstanceMethod(object_getClass(element), selector) else { return .null }
            return unsafeBitCast(method_getImplementation(method), to: Bounds.self)(element, selector, range)
        }

        private static func call(_ target: AnyObject, _ name: String) -> AnyObject? {
            let selector = NSSelectorFromString(name)
            guard target.responds(to: selector) else { return nil }
            return target.perform(selector)?.takeUnretainedValue()
        }

        private static func range(_ target: AnyObject, _ name: String) -> NSRange? {
            typealias Range = @convention(c) (AnyObject, Selector) -> NSRange
            let selector = NSSelectorFromString(name)
            guard let method = class_getInstanceMethod(object_getClass(target), selector) else { return nil }
            return unsafeBitCast(method_getImplementation(method), to: Range.self)(target, selector)
        }
    }
#endif
