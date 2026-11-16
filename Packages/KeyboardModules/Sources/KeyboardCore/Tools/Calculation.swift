/// The bar's calculator: a calculation or a unit conversion ending at the caret, and its answer, which a tap types in its
/// place (docs/design.md, "Calculator").
public struct Calculation: Hashable, Sendable {
    /// The text the answer replaces, at the end of the text before the caret; empty after an "=", which the answer
    /// follows.
    public var replacing: String
    public var answer: String

    /// The calculation the text before the caret ends with: the longest run of its last line that reads as one, so
    /// words before it stay, but not one that goes on a number, a unit or an operator before it, since that number
    /// belongs to what it reads. A lone "-", "/" or "x" between numbers reads as a range, a date, a phone number or a
    /// size until it has spaces around it or an "=" after it. Numbers are read and written with `mark` before their
    /// fractions, as the keyboard's language writes them (`Language.decimalMark`); with no `mark`, where the languages
    /// typed write them differently, only whole numbers are, since either way could be wrong.
    public init?(before text: String, mark: Character? = ".") {
        let whole = text.split(separator: "\n", omittingEmptySubsequences: false).last ?? ""
        let line = whole.suffix(160)
        var tokens = Token.read(line, mark: mark)
        let equals = tokens.last?.kind == .equals
        if equals { tokens.removeLast() }
        guard !tokens.isEmpty, line.last.map({ equals || !$0.isWhitespace }) == true else { return nil }
        let cut = line.startIndex > whole.startIndex
        for start in tokens.indices where (start > 0 || !cut) && tokens[start].follows(in: line) {
            if Self.continues(tokens[..<start], in: line) { continue }
            let run = Array(tokens[start...])
            let alone = start == 0 && !cut
            guard
                let answer = Self.conversion(run, in: line, alone: alone || equals)
                    ?? Self.calculation(run, equals: equals)
            else { continue }
            if mark == nil, answer.contains(".") { return nil }
            self.replacing = equals ? "" : String(line[run[0].range.lowerBound...])
            self.answer = mark.map { mark in String(answer.map { $0 == "." ? mark : $0 }) } ?? answer
            return
        }
        return nil
    }

    /// Whether a run after `tokens` would be the end of something longer: a number, an operator, a parenthesis or a
    /// number's unit comes right before it ("1 000 + 1", "9:30 - 10", "5 feet 6 inches in cm").
    private static func continues(_ tokens: ArraySlice<Token>, in line: Substring) -> Bool {
        guard let last = tokens.last else { return false }
        switch last.kind {
        case .number, .operation, .open, .percent: return true
        case .word:
            guard tokens.count > 1, case .number = tokens[tokens.endIndex - 2].kind else { return false }
            return Unit.named(tokens.suffix(1), in: line) != nil
        default: return false
        }
    }

    private static func calculation(_ tokens: [Token], equals: Bool) -> String? {
        var parser = Parser(tokens: tokens)
        guard let value = parser.expression(), parser.isDone, !parser.operators.isEmpty,
            equals || parser.operators.contains(where: { !["-", "/", "x"].contains($0.symbol) || $0.spaced })
        else { return nil }
        return value.percent
            ? Self.format(value.number * 100, significant: 12).map { $0 + "%" }
            : Self.format(value.number, significant: 12)
    }

    /// "10 km in mi": an amount, its unit, "in", "to", "as" or "into", and the unit to give it in, by name or by a
    /// symbol of two letters or more unless the conversion is the whole line, since "in m" may be "in my" on its way.
    private static func conversion(_ tokens: [Token], in line: Substring, alone: Bool) -> String? {
        for (index, token) in tokens.enumerated() where ["in", "to", "as", "into"].contains(token.word) {
            guard let (to, typed) = Unit.named(tokens[(index + 1)...], in: line), alone || typed.count > 1 else {
                continue
            }
            for split in [index - 2, index - 1] where split > 0 {
                guard let (from, _) = Unit.named(tokens[split..<index], in: line), from.dimension == to.dimension else {
                    continue
                }
                var parser = Parser(tokens: Array(tokens[..<split]))
                guard let value = parser.expression(), parser.isDone,
                    let answer = format(to.amount(fromBase: from.base(value.number)), significant: 6)
                else { continue }
                return answer + " " + (typed.count > 2 ? typed : to.symbol)
            }
        }
        return nil
    }

    /// The number with up to `significant` digits, without trailing zeros, in e notation from 15 digits before the
    /// point or 10 zeros after it.
    static func format(_ number: Double, significant: Int) -> String? {
        guard number.isFinite else { return nil }
        guard number != 0 else { return "0" }
        let sign = number < 0 ? "-" : ""
        var mantissa = number.magnitude
        var exponent = 0
        while mantissa >= 10 { (mantissa, exponent) = (mantissa / 10, exponent + 1) }
        while mantissa < 1 { (mantissa, exponent) = (mantissa * 10, exponent - 1) }
        var scale = 1.0
        for _ in 1..<significant { scale *= 10 }
        if (mantissa * scale).rounded() >= 10 * scale { (mantissa, exponent) = (1, exponent + 1) }
        if exponent >= 15 || exponent < -9 {
            return fixed(mantissa, decimals: significant - 1).map {
                sign + $0 + "e" + (exponent > 0 ? "+" : "") + "\(exponent)"
            }
        }
        return fixed(number.magnitude, decimals: max(significant - 1 - exponent, 0)).map { sign + $0 }
    }

    private static func fixed(_ magnitude: Double, decimals: Int) -> String? {
        var scale = 1.0
        for _ in 0..<decimals { scale *= 10 }
        let scaled = (magnitude * scale).rounded()
        guard scaled < 1e18 else { return nil }
        var digits = String(UInt64(scaled))
        if digits.count <= decimals { digits = String(repeating: "0", count: decimals + 1 - digits.count) + digits }
        guard decimals > 0 else { return digits }
        let point = digits.index(digits.endIndex, offsetBy: -decimals)
        let fraction = digits[point...].reversed().drop { $0 == "0" }.reversed()
        return digits[..<point] + (fraction.isEmpty ? "" : "." + String(fraction))
    }
}

/// A piece of a calculation as typed.
struct Token: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case number(Double)
        case operation(Character)
        /// "of", after a percentage.
        case of
        case open, close, percent, equals
        case word(String)
        case other
    }

    var kind: Kind
    var range: Range<String.Index>
    var spaceBefore: Bool

    var word: String? {
        if case .word(let word) = kind { word } else { nil }
    }

    /// Whether a calculation may start here: at the line's start, after a space, or after a quote.
    func follows(in line: Substring) -> Bool {
        guard range.lowerBound > line.startIndex else { return true }
        let before = line[line.index(before: range.lowerBound)]
        return before.isWhitespace || "\"“'‘".contains(before)
    }

    static func read(_ line: Substring, mark: Character?) -> [Token] {
        var tokens: [Token] = []
        var index = line.startIndex
        var space = false
        func take(_ kind: Kind, to end: String.Index) {
            tokens.append(Token(kind: kind, range: index..<end, spaceBefore: space))
            index = end
            space = false
        }
        while index < line.endIndex {
            let character = line[index]
            let next = line.index(after: index)
            if character.isWhitespace {
                space = true
                index = next
            } else if character.isNumber || character == mark && next < line.endIndex && line[next].isNumber {
                let end = mark == "." ? numberEnd(in: line, from: index) : marksEnd(in: line, from: index)
                take(number(line[index..<end], mark: mark).map(Kind.number) ?? .other, to: end)
            } else if character.isLetter || "°".contains(character) {
                var end = line[index...].firstIndex { !($0.isLetter || "°²³".contains($0)) } ?? line.endIndex
                if end < line.endIndex, line[end] == "/", line.index(after: end) < line.endIndex,
                    line[line.index(after: end)].isLetter
                {
                    end = line[line.index(after: end)...].firstIndex { !$0.isLetter } ?? line.endIndex
                }
                let word = String(line[index..<end]).lowercased()
                take(word == "x" ? .operation("x") : word == "of" ? .of : .word(word), to: end)
            } else {
                let kind: Kind =
                    switch character {
                    case "+": .operation("+")
                    case "-", "−": .operation("-")
                    case "*", "×", "·": .operation("×")
                    case "/", "÷": .operation("/")
                    case "^": .operation("^")
                    case "(": .open
                    case ")": .close
                    case "%": .percent
                    case "=": .equals
                    default: .other
                    }
                take(kind, to: next)
            }
        }
        return tokens
    }

    /// A number as written with `mark` before its fraction. Where the mark is a comma, a point in it could group
    /// thousands (1.500 in German) or be a fraction typed the English way, and so could a comma before three digits
    /// (1,500), so these read as no number.
    private static func number(_ written: Substring, mark: Character?) -> Double? {
        guard mark != "." else { return Double(written.filter { $0 != "," }) }
        guard mark != nil else { return written.allSatisfy(\.isNumber) ? Double(String(written)) : nil }
        let parts = written.split(separator: ",", omittingEmptySubsequences: false)
        guard !written.contains("."), parts.count <= 2, parts.count == 1 || parts[1].count != 3 || parts[0] == "0"
        else { return nil }
        return Double(String(written.map { $0 == "," ? "." : $0 }))
    }

    /// Where a number ends when its fraction follows a comma: digits, and any points or commas between digits, so
    /// what `number` can't read is left out whole.
    private static func marksEnd(in line: Substring, from start: String.Index) -> String.Index {
        var end = line[start...].firstIndex { !$0.isNumber } ?? line.endIndex
        while end < line.endIndex, ".,".contains(line[end]), line.index(after: end) < line.endIndex,
            line[line.index(after: end)].isNumber
        {
            end = line[line.index(after: end)...].firstIndex { !$0.isNumber } ?? line.endIndex
        }
        return end
    }

    /// Where a number ends: digits, groups of three after commas, and a fraction after a point.
    private static func numberEnd(in line: Substring, from start: String.Index) -> String.Index {
        var end = line[start...].firstIndex { !$0.isNumber } ?? line.endIndex
        while end < line.endIndex, line[end] == "," {
            let group = line[line.index(after: end)...].prefix(4)
            guard group.prefix(3).count == 3, group.prefix(3).allSatisfy(\.isNumber),
                group.count < 4 || !group.last!.isNumber
            else { break }
            end = line.index(end, offsetBy: 4)
        }
        if end < line.endIndex, line[end] == ".", line.index(after: end) < line.endIndex,
            line[line.index(after: end)].isNumber
        {
            end = line[line.index(after: end)...].firstIndex { !$0.isNumber } ?? line.endIndex
        }
        return end
    }
}

/// Reads tokens as arithmetic, by precedence: + and - under × and /, under a sign, under ^, under % and "of".
struct Parser {
    struct Value {
        var number: Double
        /// A percentage, which + and - take of what they add it to: 80 + 20% is 96, and 50% + 20% is 70%.
        var percent = false
    }

    struct Operator {
        var symbol: String
        var spaced: Bool
    }

    let tokens: [Token]
    var index = 0
    private(set) var operators: [Operator] = []

    init(tokens: [Token]) {
        self.tokens = tokens
    }

    var isDone: Bool { index == tokens.count }

    mutating func expression() -> Value? {
        guard var value = term() else { return nil }
        while let symbol = take("+-") {
            guard let right = term() else { return nil }
            let amount = right.percent && !value.percent ? value.number * right.number : right.number
            let sum = symbol == "+" ? value.number + amount : value.number - amount
            let noise = max(value.number.magnitude, amount.magnitude) * 1e-14
            value = Value(number: sum.magnitude < noise ? 0 : sum, percent: value.percent && right.percent)
        }
        return value
    }

    private mutating func term() -> Value? {
        guard var value = signed() else { return nil }
        while let symbol = take("×x/") {
            guard let right = signed(), symbol != "/" || right.number != 0 else { return nil }
            value = Value(number: symbol == "/" ? value.number / right.number : value.number * right.number)
        }
        return value
    }

    /// A minus sign touches its number: a spaced one is a dash ("- 5 + 3" is a list item).
    private mutating func signed() -> Value? {
        guard next == .operation("-") else { return power() }
        index += 1
        guard index < tokens.count, !tokens[index].spaceBefore else { return nil }
        return signed().map { Value(number: -$0.number, percent: $0.percent) }
    }

    private mutating func power() -> Value? {
        guard let base = postfix() else { return nil }
        guard take("^") != nil else { return base }
        guard let exponent = signed(), let raised = Self.raise(base.number, to: exponent.number) else { return nil }
        return Value(number: raised)
    }

    private mutating func postfix() -> Value? {
        guard var value = primary() else { return nil }
        guard next == .percent else { return value }
        index += 1
        value = Value(number: value.number / 100, percent: true)
        guard next == .of else { return value }
        operators.append(Operator(symbol: "of", spaced: true))
        index += 1
        return signed().map { Value(number: value.number * $0.number) }
    }

    private mutating func primary() -> Value? {
        guard let token = next else { return nil }
        index += 1
        switch token {
        case .number(let number):
            return Value(number: number)
        case .open:
            guard let value = expression(), next == .close else { return nil }
            index += 1
            return Value(number: value.number)
        default:
            return nil
        }
    }

    private var next: Token.Kind? { index < tokens.count ? tokens[index].kind : nil }

    /// Takes a binary operator from `symbols` if one is next, noting it and whether a space sits on either side.
    private mutating func take(_ symbols: String) -> Character? {
        guard case .operation(let symbol) = next, symbols.contains(symbol) else { return nil }
        let spaced = tokens[index].spaceBefore || index + 1 < tokens.count && tokens[index + 1].spaceBefore
        operators.append(Operator(symbol: String(symbol), spaced: spaced))
        index += 1
        return symbol
    }

    /// Whole powers only, multiplied out, since KeyboardCore has no `pow`.
    private static func raise(_ base: Double, to exponent: Double) -> Double? {
        guard exponent == exponent.rounded(), exponent.magnitude <= 1024 else { return nil }
        var result = 1.0
        for _ in 0..<Int(exponent.magnitude) { result *= base }
        return exponent < 0 ? 1 / result : result
    }
}
