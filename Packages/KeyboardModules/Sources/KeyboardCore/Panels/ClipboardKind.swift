extension ClipboardHistory.Item.Content {
    /// What a copied text is, so a row can show a link as its site and an address, a number or a color by its own glyph.
    public enum Kind: Hashable, Sendable {
        case text
        case image
        case link(ClipLink)
        case email
        case phone
        case color(red: UInt8, green: UInt8, blue: UInt8)
    }

    public var kind: Kind {
        switch self {
        case .image: return .image
        case .textFile: return .text
        case .text(let text):
            let trimmed = text.trimmed
            guard !trimmed.isEmpty, trimmed.count <= 2048,
                !trimmed.contains(where: \.isWhitespace) || Self.isPhone(trimmed)
            else { return .text }
            if let link = ClipLink(trimmed) { return .link(link) }
            if let color = Self.color(trimmed) { return color }
            if Self.isEmail(trimmed) { return .email }
            if Self.isPhone(trimmed) { return .phone }
            return .text
        }
    }

    private static func isEmail(_ text: String) -> Bool {
        let parts = text.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, let dot = parts[1].lastIndex(of: "."), dot != parts[1].startIndex
        else { return false }
        let top = parts[1][parts[1].index(after: dot)...]
        return top.count >= 2 && top.allSatisfy(\.isLetter)
    }

    /// Digits with a phone number's punctuation: ten or more of them, or fewer after a +, so a date or a code stays text.
    private static func isPhone(_ text: String) -> Bool {
        guard text.allSatisfy({ $0.isASCII && ($0.isNumber || " +-().".contains($0)) }), !text.contains("..") else {
            return false
        }
        let digits = text.filter(\.isNumber).count
        return (text.hasPrefix("+") ? 7 : 10)...15 ~= digits
    }

    /// `#rgb` or `#rrggbb`.
    private static func color(_ text: String) -> Kind? {
        guard text.first == "#" else { return nil }
        var hex = Array(text.dropFirst())
        if hex.count == 3 { hex = hex.flatMap { [$0, $0] } }
        guard hex.count == 6, let value = UInt32(String(hex), radix: 16) else { return nil }
        return .color(red: UInt8(value >> 16 & 0xFF), green: UInt8(value >> 8 & 0xFF), blue: UInt8(value & 0xFF))
    }
}

/// A copied web link as a row shows it, ChatGPT's way: its site, `x.com`, then its path, `/vercel/status/1985…`, without
/// the query or fragment that only track or scroll. The whole link is what's typed.
public struct ClipLink: Hashable, Sendable {
    /// Lowercase, without `www.`.
    public var site: String
    /// From its first `/`, without a trailing one; empty for a site's home page.
    public var path: String

    /// The site as ChatGPT's source pills name it, for where a whole site won't fit: `github`, `wikipedia`, `bbc`, `x`.
    public var name: String {
        let labels = site.split(separator: ".")
        let country = labels.count >= 3 && labels[labels.count - 1].count == 2 && labels[labels.count - 2].count <= 3
        return String(labels[labels.count - (country ? 3 : 2)])
    }

    public init(site: String, path: String) {
        self.site = site
        self.path = path
    }

    public init?(_ text: String) {
        let lower = text.lowercased()
        guard let scheme = ["https://", "http://"].first(where: lower.hasPrefix) else { return nil }
        let rest = text.dropFirst(scheme.count)
        let hostEnd = rest.firstIndex { "/?#".contains($0) } ?? rest.endIndex
        var host = rest[..<hostEnd].lowercased()
        if let at = host.lastIndex(of: "@") { host = String(host[host.index(after: at)...]) }
        if let colon = host.firstIndex(of: ":") { host = String(host[..<colon]) }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        guard host.contains("."), !host.hasPrefix("."), !host.hasSuffix("."),
            host.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") })
        else { return nil }
        let after = rest[hostEnd...]
        var path = String(after.prefix { $0 != "?" && $0 != "#" })
        while path.hasSuffix("/") { path.removeLast() }
        site = host
        self.path = path
    }
}

extension String {
    fileprivate var trimmed: String {
        let start = firstIndex { !$0.isWhitespace } ?? endIndex
        let end = lastIndex { !$0.isWhitespace }.map(index(after:)) ?? start
        return String(self[start..<max(start, end)])
    }
}
