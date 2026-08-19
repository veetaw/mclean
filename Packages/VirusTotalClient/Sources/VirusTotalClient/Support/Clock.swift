import Foundation

/// Abstraction over "what time is it now", so the rate limiter's real
/// wait/backoff behavior can be driven by a deterministic fake clock in
/// tests instead of depending on real wall-clock time. Mirrors the
/// `Clock`/`SystemClock` pattern already used in `MenuBarAgent` and
/// `SafetyRules`.
public protocol Clock: Sendable {
    func now() -> Date
}

/// The real clock, backed by `Date()`.
public struct SystemClock: Clock {
    public init() {}
    public func now() -> Date { Date() }
}
