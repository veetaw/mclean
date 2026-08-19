import Foundation

/// Pure, timer-free coalescing state machine: records raw event arrivals and
/// answers "has it been quiet for `quietPeriod` since the last one?".
///
/// Kept deliberately separate from any real timer so the debounce *decision*
/// logic used to turn a burst of FSEvents callbacks into a single "maybe
/// re-scan" signal can be unit tested by feeding it fake timestamps, with no
/// real waiting involved. `ChangeSignalCoalescer` is the actor that drives
/// this with a real (or fake, in tests) clock + sleeper.
public struct EventCoalescer: Sendable {
    public let quietPeriod: TimeInterval
    private var lastEventAt: Date?

    public init(quietPeriod: TimeInterval) {
        self.quietPeriod = quietPeriod
    }

    /// A raw event arrived at `now`.
    public mutating func recordEvent(at now: Date) {
        lastEventAt = now
    }

    /// Whether `quietPeriod` has elapsed since the last recorded event.
    /// Firing consumes the pending state: the next call returns `false`
    /// until another event is recorded.
    public mutating func shouldFire(at now: Date) -> Bool {
        guard let lastEventAt else { return false }
        guard now.timeIntervalSince(lastEventAt) >= quietPeriod else { return false }
        self.lastEventAt = nil
        return true
    }

    /// Whether an event is currently pending (waiting out its quiet period).
    public var hasPendingEvent: Bool { lastEventAt != nil }
}
