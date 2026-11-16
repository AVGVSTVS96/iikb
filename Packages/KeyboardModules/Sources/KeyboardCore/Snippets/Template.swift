/// A snippet's text or a quicklink's link with Raycast's placeholders read out of it: `{cursor}`, where the caret ends,
/// and `{argument}`, a value asked for before it goes in, which may be named and have a default
/// (`{argument name="City" default="Paris"}`). Arguments with one name share a value; each unnamed one is its own. The
/// quotes may be curly, as a phone types them. Any other text in braces is kept as written.
public struct Template: Hashable, Sendable {
    public struct Argument: Hashable, Sendable {
        public var name: String
        public var defaultValue: String

        public init(name: String, defaultValue: String = "") {
            self.name = name
            self.defaultValue = defaultValue
        }
    }

    enum Part: Hashable, Sendable {
        case text(String)
        case cursor
        case argument(Int)
    }

    let parts: [Part]
    public let arguments: [Argument]

    public init(_ source: String) {
        var parts: [Part] = []
        var arguments: [Argument] = []
        var named: [String: Int] = [:]
        var unnamed = 0
        var text = ""
        var rest = Substring(source)
        while let open = rest.firstIndex(of: "{") {
            text += rest[..<open]
            guard let close = rest[open...].firstIndex(of: "}"),
                let placeholder = Self.placeholder(rest[rest.index(after: open)..<close])
            else {
                text.append("{")
                rest = rest[rest.index(after: open)...]
                continue
            }
            if !text.isEmpty { parts.append(.text(text)) }
            text = ""
            rest = rest[rest.index(after: close)...]
            switch placeholder {
            case .cursor:
                if !parts.contains(.cursor) { parts.append(.cursor) }
            case .argument(let name, let defaultValue):
                if let name, let index = named[name] {
                    parts.append(.argument(index))
                    continue
                }
                if name == nil { unnamed += 1 }
                if let name { named[name] = arguments.count }
                parts.append(.argument(arguments.count))
                arguments.append(Argument(name: name ?? "", defaultValue: defaultValue))
            }
        }
        text += rest
        if !text.isEmpty { parts.append(.text(text)) }
        self.parts = parts
        self.arguments = arguments.enumerated().map { index, argument in
            guard argument.name.isEmpty else { return argument }
            let number = arguments[...index].filter(\.name.isEmpty).count
            return Argument(name: unnamed > 1 ? "Argument \(number)" : "Argument", defaultValue: argument.defaultValue)
        }
    }

    /// The text with each argument's value in its place, its default where the value is empty, each passed through
    /// `encode` (a link percent-encodes them), and where `{cursor}` was, in characters from the start.
    public func filled(_ values: [String] = [], encode: (String) -> String = { $0 }) -> (text: String, cursor: Int?) {
        var text = ""
        var cursor: Int?
        for part in parts {
            switch part {
            case .text(let string):
                text += string
            case .cursor:
                cursor = text.count
            case .argument(let index):
                let value = index < values.count ? values[index] : ""
                text += encode(value.isEmpty ? arguments[index].defaultValue : value)
            }
        }
        return (text, cursor)
    }

    /// `value` as it goes into a link: every byte but letters, digits and `-._~` percent-encoded.
    public static func percentEncoded(_ value: String) -> String {
        var encoded = ""
        for byte in value.utf8 {
            switch byte {
            case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "A")...UInt8(ascii: "Z"),
                UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "-"), UInt8(ascii: "."), UInt8(ascii: "_"),
                UInt8(ascii: "~"):
                encoded.unicodeScalars.append(Unicode.Scalar(byte))
            default:
                let hex = String(byte, radix: 16, uppercase: true)
                encoded += "%" + (hex.count == 1 ? "0" : "") + hex
            }
        }
        return encoded
    }

    private enum Placeholder {
        case cursor
        case argument(name: String?, defaultValue: String)
    }

    /// What's between a pair of braces, if it's a placeholder.
    private static func placeholder(_ inside: Substring) -> Placeholder? {
        let words = inside.drop(while: \.isWhitespace)
        if words.trimmingTrailingSpaces() == "cursor" { return .cursor }
        guard words.hasPrefix("argument") else { return nil }
        let attributes = words.dropFirst("argument".count)
        guard attributes.first?.isWhitespace ?? true else { return nil }
        let values = Self.attributes(attributes)
        return .argument(name: values["name"].flatMap { $0.isEmpty ? nil : $0 }, defaultValue: values["default"] ?? "")
    }

    /// `name="City" default="Paris"`, with straight or curly quotes.
    private static func attributes(_ text: Substring) -> [String: String] {
        var values: [String: String] = [:]
        var rest = text
        while let equals = rest.firstIndex(of: "=") {
            let key = String(rest[..<equals].trimmingSpaces())
            rest = rest[rest.index(after: equals)...].drop(while: \.isWhitespace)
            guard let quote = rest.first, quotes.contains(quote) else { break }
            rest = rest.dropFirst()
            let end = rest.firstIndex(where: quotes.contains) ?? rest.endIndex
            values[key] = String(rest[..<end])
            rest = end < rest.endIndex ? rest[rest.index(after: end)...] : rest[end...]
        }
        return values
    }

    private static let quotes: Set<Character> = ["\"", "“", "”", "„", "'", "‘", "’"]
}

extension Substring {
    func trimmingTrailingSpaces() -> Substring {
        var trimmed = self
        while trimmed.last?.isWhitespace == true { trimmed.removeLast() }
        return trimmed
    }

    func trimmingSpaces() -> Substring {
        drop(while: \.isWhitespace).trimmingTrailingSpaces()
    }
}
