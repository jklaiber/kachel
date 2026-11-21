import Foundation

/// The time as WindowManager sees it: what time it is, and work to do a bit
/// later. SystemClock is the real one; the tests use one that only moves when
/// told, so "after a minute" takes no time at all.
protocol Clock: AnyObject {
    var now: Date { get }
    /// Run `work` on the main thread `seconds` from now.
    func after(_ seconds: TimeInterval, _ work: @escaping () -> Void)
}

final class SystemClock: Clock {
    var now: Date { Date() }
    func after(_ seconds: TimeInterval, _ work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }
}
