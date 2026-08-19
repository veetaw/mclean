import Foundation

/// Checks free disk space against `threshold` (each time `checkNow()` is
/// called, e.g. from a caller's own periodic timer) and posts a low-space
/// notification when crossed, with a `cooldown` so a persistently-low
/// condition doesn't spam a fresh notification on every check.
///
/// Notify-again rules:
/// - Crossing from OK to low always notifies immediately.
/// - While it stays low, it re-notifies only after `cooldown` has elapsed
///   since the last notification.
/// - Recovering above the threshold resets state, so the *next* time it goes
///   low it notifies immediately again, rather than still being under the
///   old cooldown from the previous low period.
public actor LowDiskSpaceMonitor {
    private let path: String
    private let threshold: LowDiskSpaceThreshold
    private let cooldown: TimeInterval
    private let diskSpaceProvider: DiskSpaceProviding
    private let notifier: NotificationPosting
    private let clock: Clock

    private var lastNotifiedAt: Date?

    public init(
        path: String = NSHomeDirectory(),
        threshold: LowDiskSpaceThreshold = .default,
        cooldown: TimeInterval = 6 * 60 * 60,
        diskSpaceProvider: DiskSpaceProviding = StatfsDiskSpaceProvider(),
        notifier: NotificationPosting,
        clock: Clock = SystemClock()
    ) {
        self.path = path
        self.threshold = threshold
        self.cooldown = cooldown
        self.diskSpaceProvider = diskSpaceProvider
        self.notifier = notifier
        self.clock = clock
    }

    /// Runs one check. Returns whether the volume is currently low on space,
    /// independent of whether a notification was actually posted this time
    /// (it may have been suppressed by the cooldown) -- callers can use the
    /// return value to drive UI state (e.g. a warning icon) separately from
    /// notification delivery.
    @discardableResult
    public func checkNow() async -> Bool {
        guard let (free, total) = try? diskSpaceProvider.freeAndTotalBytes(atPath: path) else {
            return false
        }

        guard threshold.isLow(free: free, total: total) else {
            lastNotifiedAt = nil
            return false
        }

        let now = clock.now()
        if let lastNotifiedAt, now.timeIntervalSince(lastNotifiedAt) < cooldown {
            return true
        }

        lastNotifiedAt = now
        await notifier.post(
            identifier: "pro.mclean.low-disk-space",
            title: "Low Disk Space",
            body: Self.body(free: free)
        )
        return true
    }

    private static func body(free: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let freeText = formatter.string(fromByteCount: free)
        return "Only \(freeText) free. Run a scan in MClean Pro to reclaim space."
    }
}
