import Foundation

/// Backstop refresh timer. Independent of FSEvents so we still update if events get missed
/// (e.g. across sleep/wake) or while no file changes are happening.
@MainActor
final class PollTimer {
    private var timer: Timer?
    private var interval: TimeInterval
    private let onTick: @MainActor () -> Void

    init(interval: TimeInterval, onTick: @escaping @MainActor () -> Void) {
        self.interval = interval
        self.onTick = onTick
    }

    func start() {
        stop()
        let t = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.onTick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func setInterval(_ newInterval: TimeInterval) {
        guard newInterval != interval else { return }
        interval = newInterval
        if timer != nil { start() }
    }
}
