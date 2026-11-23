public struct TrackpadDrag: Sendable {
    public private(set) var x: Double
    public private(set) var y: Double
    private var samples: [Sample]

    private struct Sample: Sendable {
        var time, x, y: Double
    }

    public init(x: Double, y: Double, time: Double) {
        self.x = x
        self.y = y
        samples = [Sample(time: time, x: x, y: y)]
    }

    public mutating func move(toX x: Double, y: Double, time: Double) {
        let last = samples[samples.count - 1]
        samples.append(Sample(time: max(time, last.time), x: x, y: y))
        while samples.count > 2,
            samples.count > Self.samples || samples[samples.count - 1].time - samples[1].time > Self.window
        {
            samples.removeFirst()
        }
        let gain = Self.gain(speed: speed)
        self.x += (x - last.x) * gain
        self.y += (y - last.y) * gain
    }

    var speed: Double {
        let first = samples[0]
        let last = samples[samples.count - 1]
        var distance = 0.0
        for (from, to) in zip(samples, samples.dropFirst()) {
            distance += ((to.x - from.x) * (to.x - from.x) + (to.y - from.y) * (to.y - from.y)).squareRoot()
        }
        return distance / max(last.time - first.time, Double(samples.count - 1) / 240)
    }

    static let window = 0.03
    static let samples = 8

    public static func gain(speed: Double) -> Double {
        guard speed > 1000 else { return 1 + max(0, speed - 40) / 960 }
        return min(4, 2 + (speed - 1000) / 1690)
    }
}
