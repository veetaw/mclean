import Foundation

/// Abstraction over "suspend for this long", separated out so production
/// code can use a real `Task.sleep` while tests substitute a double that
/// resumes immediately (optionally advancing a paired test `Clock`) --
/// letting the rate limiter's genuine wait/backoff logic be exercised
/// deterministically without a test actually blocking on real time. Mirrors
/// the `Sleeping`/`TaskSleeper` pattern already used in `MenuBarAgent`.
public protocol Sleeping: Sendable {
    func sleep(for seconds: TimeInterval) async
}

/// Real implementation, backed by `Task.sleep`. Cancellation surfaces as a
/// thrown `CancellationError`, which is swallowed here: callers check
/// `Task.isCancelled` (or `Task.checkCancellation()`) immediately after
/// waking up and treat a cancelled sleep the same as one that ran to
/// completion, so the cancellation is still observed promptly.
public struct TaskSleeper: Sleeping {
    public init() {}

    public func sleep(for seconds: TimeInterval) async {
        try? await Task.sleep(for: .seconds(max(0, seconds)))
    }
}
