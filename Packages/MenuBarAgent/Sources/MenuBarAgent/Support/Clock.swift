import Foundation

/// Abstraction over "what time is it now", so time-dependent logic
/// (low-disk-space cooldown, health-check scheduling, FSEvents debounce) can
/// be driven by a deterministic fake clock in tests instead of depending on
/// real wall-clock time.
public protocol Clock: Sendable {
    func now() -> Date
}

/// The real clock, backed by `Date()`.
public struct SystemClock: Clock {
    public init() {}
    public func now() -> Date { Date() }
}
