import Testing

@testable import KeyboardCore

struct TrackpadDragTests {
    private func dragged(_ distance: Double, at speed: Double, rate: Double = 120) -> Double {
        var drag = TrackpadDrag(x: 0, y: 0, time: 0)
        let steps = max(Int(distance / speed * rate), 1)
        for step in 1...steps {
            drag.move(
                toX: distance * Double(step) / Double(steps), y: 0,
                time: distance / speed * Double(step) / Double(steps))
        }
        return drag.x
    }

    @Test func aSlowDragMovesAboutAsFarAsTheFinger() {
        #expect(abs(dragged(80, at: 40) - 80) < 1)
    }

    @Test func aFasterDragGoesFurther() {
        let distances = [40.0, 400, 1000, 2000].map { dragged(160, at: $0) }
        #expect(distances == distances.sorted() && Set(distances).count == distances.count, "\(distances)")
        #expect(abs(dragged(160, at: 1000) / 160 - TrackpadDrag.gain(speed: 1000)) < 0.05)
    }

    @Test func theSpeedIsTheFingersWhateverTheTouchRate() {
        #expect(abs(dragged(160, at: 400, rate: 120) - dragged(160, at: 400, rate: 240)) < 2)
    }

    @Test func aFlickThenASlowSlideGoesAsFarAsEachAlone() {
        var drag = TrackpadDrag(x: 0, y: 0, time: 0)
        for step in 1...12 { drag.move(toX: Double(step) * 1000 / 120, y: 0, time: Double(step) / 120) }
        let flicked = drag.x
        for step in 1...60 { drag.move(toX: 100 + Double(step) * 40 / 120, y: 0, time: 0.1 + 0.1 + Double(step) / 120) }
        #expect(abs(drag.x - flicked - 20 * TrackpadDrag.gain(speed: 40)) < 1)
    }

    @Test func movesThatCarryNoTimeStillReadAsAFingersPace() {
        var drag = TrackpadDrag(x: 0, y: 0, time: 0)
        for step in 1...100 { drag.move(toX: Double(step), y: 0, time: 0) }
        #expect(drag.x < 100 * TrackpadDrag.gain(speed: 300), "\(drag.x)")
    }

    @Test func upAndDownSpeedUpAsAlongDoes() {
        var drag = TrackpadDrag(x: 0, y: 0, time: 0)
        for step in 1...12 { drag.move(toX: Double(step) * 5, y: Double(step) * 5, time: Double(step) / 120) }
        #expect(drag.x == drag.y && drag.y > 60)
    }
}
