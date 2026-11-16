/// A unit the calculator converts, as a multiple of its dimension's base unit plus an offset (temperatures).
struct Unit: Hashable, Sendable {
    enum Dimension: Hashable, Sendable { case length, mass, volume, temperature, speed, time, data, area }

    var dimension: Dimension
    /// How it's written in an answer.
    var symbol: String
    var factor: Double
    var offset = 0.0

    func base(_ amount: Double) -> Double { amount * factor + offset }
    func amount(fromBase base: Double) -> Double { (base - offset) / factor }

    /// The unit one or two words of `line` name, and how they were written there.
    static func named(_ tokens: ArraySlice<Token>, in line: Substring) -> (Unit, String)? {
        guard (1...2).contains(tokens.count), let first = tokens.first, let last = tokens.last else { return nil }
        let words = tokens.compactMap(\.word)
        guard words.count == tokens.count else { return nil }
        return names[words.joined(separator: " ")].map {
            ($0, String(line[first.range.lowerBound..<last.range.upperBound]))
        }
    }

    private static let names: [String: Unit] = {
        var names: [String: Unit] = [:]
        for (dimension, units) in table {
            for (spellings, factor, offset) in units {
                let written = spellings.split(separator: "|").map(String.init)
                let unit = Unit(dimension: dimension, symbol: written[0], factor: factor, offset: offset)
                for name in written { names[name.lowercased()] = unit }
            }
        }
        return names
    }()

    /// Each unit's spellings, the first its symbol, and its size in the dimension's first unit.
    private static let table: [(Dimension, [(String, Double, Double)])] = [
        (
            .length,
            [
                ("m|meter|meters|metre|metres", 1, 0),
                ("mm|millimeter|millimeters|millimetre|millimetres", 0.001, 0),
                ("cm|centimeter|centimeters|centimetre|centimetres", 0.01, 0),
                ("km|kms|kilometer|kilometers|kilometre|kilometres", 1000, 0),
                ("in|inch|inches", 0.0254, 0),
                ("ft|foot|feet", 0.3048, 0),
                ("yd|yds|yard|yards", 0.9144, 0),
                ("mi|mile|miles", 1609.344, 0),
                ("nmi|nautical mile|nautical miles", 1852, 0),
            ]
        ),
        (
            .mass,
            [
                ("kg|kgs|kilo|kilos|kilogram|kilograms", 1, 0),
                ("mg|milligram|milligrams", 0.000001, 0),
                ("g|gram|grams", 0.001, 0),
                ("t|tonne|tonnes", 1000, 0),
                ("oz|ounce|ounces", 0.028349523125, 0),
                ("lb|lbs|pound|pounds", 0.45359237, 0),
                ("st|stone|stones", 6.35029318, 0),
            ]
        ),
        (
            .volume,
            [
                ("L|l|liter|liters|litre|litres", 1, 0),
                ("mL|ml|milliliter|milliliters|millilitre|millilitres", 0.001, 0),
                ("cl|centiliter|centiliters|centilitre|centilitres", 0.01, 0),
                ("tsp|teaspoon|teaspoons", 0.00492892159375, 0),
                ("tbsp|tablespoon|tablespoons", 0.01478676478125, 0),
                ("fl oz|floz|fluid ounce|fluid ounces", 0.0295735295625, 0),
                ("cup|cups", 0.2365882365, 0),
                ("pt|pint|pints", 0.473176473, 0),
                ("qt|quart|quarts", 0.946352946, 0),
                ("gal|gallon|gallons", 3.785411784, 0),
            ]
        ),
        (
            .temperature,
            [
                ("K|k|kelvin", 1, 0),
                ("°C|c|celsius", 1, 273.15),
                ("°F|f|fahrenheit", 5.0 / 9, 459.67 * 5 / 9),
            ]
        ),
        (
            .speed,
            [
                ("m/s", 1, 0),
                ("km/h|kph|kmh", 1 / 3.6, 0),
                ("mph", 0.44704, 0),
                ("kn|kt|knot|knots", 1852.0 / 3600, 0),
            ]
        ),
        (
            .time,
            [
                ("s|sec|secs|second|seconds", 1, 0),
                ("ms|millisecond|milliseconds", 0.001, 0),
                ("min|mins|minute|minutes", 60, 0),
                ("h|hr|hrs|hour|hours", 3600, 0),
                ("d|day|days", 86400, 0),
                ("wk|week|weeks", 604800, 0),
                ("yr|year|years", 31_557_600, 0),
            ]
        ),
        (
            .data,
            [
                ("B|byte|bytes", 1, 0),
                ("bit|bits", 0.125, 0),
                ("KB|kilobyte|kilobytes", 1e3, 0),
                ("MB|megabyte|megabytes", 1e6, 0),
                ("GB|gigabyte|gigabytes", 1e9, 0),
                ("TB|terabyte|terabytes", 1e12, 0),
                ("KiB", 1024, 0),
                ("MiB", 1_048_576, 0),
                ("GiB", 1_073_741_824, 0),
            ]
        ),
        (
            .area,
            [
                ("m²|sq m|square meter|square meters|square metre|square metres", 1, 0),
                ("km²|sq km|square kilometer|square kilometers|square kilometre|square kilometres", 1e6, 0),
                ("ft²|sq ft|square foot|square feet", 0.09290304, 0),
                ("mi²|sq mi|square mile|square miles", 2_589_988.110336, 0),
                ("acre|acres", 4046.8564224, 0),
                ("ha|hectare|hectares", 10000, 0),
            ]
        ),
    ]
}
