import Foundation

/// A simple fixed-window rate limiter keyed by peer address, applied to
/// every inbound request before it reaches routing (see
/// `RemoteControlServer`'s transport-guard middleware).
///
/// Deliberately coarse: this is a basic-hardening measure against a
/// runaway or misbehaving client on the LAN, not a defense against a
/// determined attacker — anyone reachable at all is already constrained by
/// `LANGuard`, and anything sensitive additionally requires a valid
/// per-device token.
public final class RateLimiter: @unchecked Sendable {
    private let maxRequests: Int
    private let window: TimeInterval
    private let lock = NSLock()
    private var hitsByKey: [String: [Date]] = [:]

    public init(maxRequests: Int, window: TimeInterval) {
        self.maxRequests = maxRequests
        self.window = window
    }

    /// Records one request from `key` (typically the peer address) and
    /// returns `true` if it's within the allowed rate, `false` if it should
    /// be rejected with HTTP 429.
    @discardableResult
    public func allow(_ key: String, now: Date = Date()) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        var timestamps = hitsByKey[key] ?? []
        let windowStart = now.addingTimeInterval(-window)
        timestamps.removeAll { $0 < windowStart }
        guard timestamps.count < maxRequests else {
            hitsByKey[key] = timestamps
            return false
        }
        timestamps.append(now)
        hitsByKey[key] = timestamps
        return true
    }
}
