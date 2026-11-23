import Darwin
import OSLog
import QuartzCore

@MainActor
final class FirstFrame: NSObject {
    private let made = CACurrentMediaTime()
    private var link: CADisplayLink?
    private var then: () -> Void = {}
    nonisolated private static let log = Logger(subsystem: "com.shahidy.iikb", category: "launch")

    func next(_ then: @escaping () -> Void) {
        cancel()
        self.then = then
        let link = CADisplayLink(target: self, selector: #selector(drew))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func cancel() {
        link?.invalidate()
        link = nil
    }

    @objc private func drew(_ link: CADisplayLink) {
        let shown = link.targetTimestamp
        cancel()
        let made = Int((shown - made) * 1000)
        let started = Self.started.map { Int((Date().timeIntervalSince1970 + shown - CACurrentMediaTime() - $0) * 1000) }
        Self.log.notice("first frame \(made) ms after the keyboard was made, \(started ?? -1) ms after its process started")
        then()
    }

    private static var started: TimeInterval? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var name = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&name, 4, &info, &size, nil, 0) == 0 else { return nil }
        let start = info.kp_proc.p_starttime
        return TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000
    }
}
