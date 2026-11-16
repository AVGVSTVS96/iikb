/// Where the device is set to be, which Apple's keyboard follows for its currency key and the web address endings its
/// period offers. The platform reads it (iOS's `Locale`); a part it can't tell is nil, and the keys are then the US's.
public struct Region: Hashable, Sendable {
    /// Its ISO 3166 code, as GB or SE.
    public var code: String?
    /// Its currency's ISO 4217 code, as GBP.
    public var currency: String?

    public init(code: String? = nil, currency: String? = nil) {
        self.code = code
        self.currency = currency
    }

    /// The symbol Apple's keyboard shows for its currency, or $ for one without a sign of its own.
    public var currencySymbol: String {
        currency.flatMap { Self.symbols[$0.uppercased()] } ?? "$"
    }

    private static let symbols = [
        "EUR": "€", "GBP": "£", "JPY": "¥", "CNY": "¥", "KRW": "₩", "RUB": "₽", "UAH": "₴", "INR": "₹", "TRY": "₺",
        "ILS": "₪", "PHP": "₱", "VND": "₫", "NGN": "₦", "THB": "฿", "KZT": "₸",
    ]

    /// Up to six endings for a web address, as holding the period offers them in an email, URL or search field: .com,
    /// which a hold let go types, then the region's own, the language's, and the commonest of the rest.
    public func endings(typing language: Language) -> [String] {
        let regional =
            code.map { code in
                Self.regional[code.uppercased()]
                    ?? (code.count == 2 && code.allSatisfy(\.isLetter) ? [".\(code.lowercased())"] : [])
            } ?? [".us"]
        let own = Self.languages[language.id].map { [$0] } ?? []
        var seen: Set<String> = []
        return Array(
            ([".com"] + regional + own + [".org", ".net", ".edu", ".gov"]).filter { seen.insert($0).inserted }
                .prefix(6))
    }

    /// Where a country's addresses end in more than its code, or in another.
    private static let regional = [
        "GB": [".co.uk", ".uk"], "AU": [".com.au", ".au"], "NZ": [".co.nz", ".nz"], "JP": [".jp", ".co.jp"],
        "BR": [".com.br", ".br"], "ZA": [".co.za", ".za"], "IN": [".in", ".co.in"], "MX": [".com.mx", ".mx"],
        "AR": [".com.ar", ".ar"], "KR": [".kr", ".co.kr"], "US": [".us"],
    ]

    private static let languages = ["es": ".es", "fr": ".fr", "de": ".de", "pt": ".pt", "it": ".it", "sv": ".se"]
}

/// The currency key on the number layer, as Settings › Typing picks it: the region's, as Apple's keyboard shows, or one
/// sign wherever you are.
public enum Currency: String, CaseIterable, Hashable, Sendable {
    case automatic, dollar, euro, pound, yen, won, ruble, hryvnia

    public var title: String {
        switch self {
        case .automatic: "Automatic"
        case .dollar: "$ Dollar"
        case .euro: "€ Euro"
        case .pound: "£ Pound"
        case .yen: "¥ Yen"
        case .won: "₩ Won"
        case .ruble: "₽ Ruble"
        case .hryvnia: "₴ Hryvnia"
        }
    }

    public func symbol(in region: Region) -> String {
        switch self {
        case .automatic: region.currencySymbol
        case .dollar: "$"
        case .euro: "€"
        case .pound: "£"
        case .yen: "¥"
        case .won: "₩"
        case .ruble: "₽"
        case .hryvnia: "₴"
        }
    }
}
