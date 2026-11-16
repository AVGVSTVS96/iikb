/// One touch of a swipe: where it was in points, and when, in seconds.
public struct SwipePoint: Sendable, Hashable {
    public var x: Double
    public var y: Double
    public var time: Double

    public init(x: Double, y: Double, time: Double) {
        self.x = x
        self.y = y
        self.time = time
    }
}

/// Where a keyboard's letter keys are, in the unit square the encoder reads a swipe in: the box around the letter keys
/// and their gaps, so QWERTY's keys sit at x = 0.05 … 0.95 and y = 1/6, 1/2 and 5/6. Any keyboard of letter keys
/// works, in any alphabet (FUTO's encoder reads the keys it's given), with an apostrophe key among them where it has
/// one (French's), and a letter with no key of its own is swiped on the key it's under on a long press, as it's tapped
/// there (`KeyGrid.key(holding:)`).
public struct SwipeLayout: Sendable {
    /// The most keys the encoder was made to read.
    static let mostKeys = 64
    let frame: Rect
    /// The keys' letters, lowercase, and an apostrophe where a key has one, in Unicode's order, so a keyboard of a–z
    /// gives them in the order the decoder reads.
    let letters: [String]
    let centers: [(x: Double, y: Double)]
    /// The key each letter is swiped on, by its place among `letters`: its own, or the one whose long press holds it.
    let keys: [String: Int]

    /// `centers` holds a point in the keyboard's own coordinates for each key's letter, `frame` is the box around them
    /// all, and `under` names the key each other letter is on a long press of.
    public init?(centers: [String: (x: Double, y: Double)], frame: Rect, under: [String: String] = [:]) {
        guard !centers.isEmpty, centers.count <= Self.mostKeys, frame.width > 0, frame.height > 0 else { return nil }
        self.frame = frame
        letters = centers.keys.sorted()
        self.centers = letters.map { centers[$0]! }.map {
            (($0.x - frame.x) / frame.width, ($0.y - frame.y) / frame.height)
        }
        var keys = Dictionary(uniqueKeysWithValues: letters.enumerated().map { ($1, $0) })
        for (letter, key) in under where keys[letter] == nil {
            keys[letter] = keys[key]
        }
        self.keys = keys
    }

    /// The letters of a keyboard as it is laid out now.
    public init?(grid: KeyGrid) {
        var centers: [String: (x: Double, y: Double)] = [:]
        var under: [String: String] = [:]
        var box: (minX: Double, minY: Double, maxX: Double, maxY: Double)?
        for (key, frame) in grid.rows.joined() {
            guard let letter = key.swiped else { continue }
            let cell = grid.cell(of: frame)
            centers[letter] = (frame.midX, frame.midY)
            for alternate in key.alternates where alternate.count == 1 && alternate.first!.isLetter {
                under[alternate.lowercased()] = under[alternate.lowercased()] ?? letter
            }
            box = (
                min(box?.minX ?? cell.x, cell.x), min(box?.minY ?? cell.y, cell.y),
                max(box?.maxX ?? cell.x + cell.width, cell.x + cell.width),
                max(box?.maxY ?? cell.y + cell.height, cell.y + cell.height)
            )
        }
        guard let box else { return nil }
        self.init(
            centers: centers,
            frame: Rect(x: box.minX, y: box.minY, width: box.maxX - box.minX, height: box.maxY - box.minY),
            under: under)
    }

    /// Whether its keys are a–z alone, the letters FUTO's decoder reads.
    var isAToZ: Bool { letters == Swipe.alphabet }

    /// The path as the encoder reads it: x and y in the unit square, resampled
    /// to 60 Hz and then to 64 evenly spaced points by linear interpolation.
    func resampled(_ path: [SwipePoint]) -> (x: [Float], y: [Float]) {
        let start = path[0].time
        let x = path.map { ($0.x - frame.x) / frame.width }
        let y = path.map { ($0.y - frame.y) / frame.height }
        let time = path.map { ($0.time - start) * 1000 }
        var rx = x
        var ry = y
        if let end = time.last, end > 1e-3 {
            let count = max(2, Int((end / (1000.0 / 60)).rounded(.toNearestOrEven)) + 1)
            let grid = (0..<count).map { end * Double($0) / Double(count - 1) }
            rx = Swipe.interpolate(grid, time, x)
            ry = Swipe.interpolate(grid, time, y)
        }
        let index = (0..<Swipe.inputSteps).map { Double(rx.count - 1) * Double($0) / Double(Swipe.inputSteps - 1) }
        let at = (0..<rx.count).map(Double.init)
        return (Swipe.interpolate(index, at, rx).map(Float.init), Swipe.interpolate(index, at, ry).map(Float.init))
    }
}

extension Swipe {
    /// `values` read at each of the ascending `points`, linearly between the ascending `positions` they are given at.
    static func interpolate(_ points: [Double], _ positions: [Double], _ values: [Double]) -> [Double] {
        var segment = 0
        return points.map { point in
            while segment < positions.count - 2, positions[segment + 1] < point { segment += 1 }
            let (a, b) = (positions[segment], positions[segment + 1])
            guard b > a else { return values[segment] }
            let fraction = min(max((point - a) / (b - a), 0), 1)
            return values[segment] + (values[segment + 1] - values[segment]) * fraction
        }
    }
}

extension Key {
    /// What a swipe reads on the key, lowercase: its letter, or an apostrophe; nil for any other key.
    var swiped: String? {
        guard let label = label?.lowercased(), label.count == 1, label.first!.isLetter || label == "'" else {
            return nil
        }
        return label
    }
}
