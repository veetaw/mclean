import Foundation

/// Abstraction over "suspend for this long", separated out so production
/// code can use a real `Task.sleep` while tests substitute an
/// externally-controllable double -- letting the *decision* logic that runs
/// after the wait (should this fire now, given the clock?) be exercised
/// deterministically, without the test actually blocking on real time.
public protocol Sleeping: Sendable {
    func sleep(for seconds: TimeInterval) async
}

/// Real implementation, backed by `Task.sleep`. Cancellation surfaces as a
/// thrown `CancellationError`, which is swallowed here: callers check
/// `Task.isCancelled` immediately after waking up and treat a cancelled sleep
/// the same as one that ran to completion.
public struct TaskSleeper: Sleeping {
    public init() {}

    public func sleep(for seconds: TimeInterval) async {
        try? await Task.sleep(for: .seconds(seconds))
    }
}
