import Foundation

/// How often the background health-check scan should run.
public struct HealthCheckSchedule: Sendable, Hashable {
    public var interval: TimeInterval

    public init(interval: TimeInterval) {
        self.interval = interval
    }

    public static let daily = HealthCheckSchedule(interval: 24 * 60 * 60)
    public static let weekly = HealthCheckSchedule(interval: 7 * 24 * 60 * 60)
}

/// Pure due-date logic, decoupled from any real timer, so "is a health check
/// due" can be unit tested with fake timestamps instead of a real wait.
public struct HealthCheckDueCalculator: Sendable {
    public init() {}

    /// `true` if a health check has never run, or if `schedule.interval` has
    /// elapsed since the last one.
    public func isDue(now: Date, lastRunAt: Date?, schedule: HealthCheckSchedule) -> Bool {
        guard let lastRunAt else { return true }
        return now.timeIntervalSince(lastRunAt) >= schedule.interval
    }
}
