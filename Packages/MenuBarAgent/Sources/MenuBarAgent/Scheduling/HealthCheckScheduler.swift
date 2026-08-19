import CoreScanEngine
import Foundation

/// Summary of a completed scheduled health-check scan -- used for the
/// notification body, and available to any UI that wants the raw numbers.
public struct HealthCheckSummary: Sendable, Hashable {
    public let itemCount: Int
    public let totalReclaimableBytes: Int64
    public let failedDetectorIDs: [String]
    public let ranAt: Date
}

/// Periodically runs a scan via an injected `ScanEngine` and posts a summary
/// notification. This type does not decide *which* detectors run -- that's
/// entirely up to how the caller configures the `ScanEngine` and
/// `ScanContext` it's constructed with. Like every other type in this
/// package, it only observes and notifies: it never deletes, quarantines, or
/// otherwise acts on what the scan finds.
public actor HealthCheckScheduler {
    private let schedule: HealthCheckSchedule
    private let scanEngine: ScanEngine
    private let scanContext: ScanContext
    private let notifier: NotificationPosting
    private let clock: Clock
    private let sleeper: Sleeping
    private let dueCalculator = HealthCheckDueCalculator()

    /// How often to *check* whether a run is due -- independent of
    /// `schedule` itself, and small relative to it, so the actual run
    /// happens reasonably close to when it becomes due without polling the
    /// filesystem/CPU tightly.
    private let pollInterval: TimeInterval

    private(set) var lastRunAt: Date?
    private var runLoopTask: Task<Void, Never>?

    public init(
        schedule: HealthCheckSchedule = .weekly,
        scanEngine: ScanEngine,
        scanContext: ScanContext,
        notifier: NotificationPosting,
        clock: Clock = SystemClock(),
        sleeper: Sleeping = TaskSleeper(),
        pollInterval: TimeInterval = 60 * 60
    ) {
        self.schedule = schedule
        self.scanEngine = scanEngine
        self.scanContext = scanContext
        self.notifier = notifier
        self.clock = clock
        self.sleeper = sleeper
        self.pollInterval = pollInterval
    }

    /// Starts the background poll loop. Safe to call multiple times (no-op
    /// while already running).
    public func start() {
        guard runLoopTask == nil else { return }
        runLoopTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.runIfDue()
                guard !Task.isCancelled else { return }
                await self.waitOnePollInterval()
            }
        }
    }

    public func stop() {
        runLoopTask?.cancel()
        runLoopTask = nil
    }

    private func waitOnePollInterval() async {
        await sleeper.sleep(for: pollInterval)
    }

    /// Runs the scan immediately if the schedule says it's due, updating
    /// `lastRunAt` and posting a summary notification. Exposed directly (in
    /// addition to the internal poll loop) so both tests and a caller
    /// wanting an explicit "check now" action can drive it deterministically
    /// without waiting on the poll loop.
    @discardableResult
    public func runIfDue() async -> Bool {
        let now = clock.now()
        guard dueCalculator.isDue(now: now, lastRunAt: lastRunAt, schedule: schedule) else {
            return false
        }
        lastRunAt = now

        let result = await scanEngine.runAll(context: scanContext)
        let summary = HealthCheckSummary(
            itemCount: result.items.count,
            totalReclaimableBytes: result.items.reduce(Int64(0)) { $0 + ($1.sizeBytes ?? 0) },
            failedDetectorIDs: result.failedDetectorIDs.keys.sorted(),
            ranAt: now
        )
        await notifier.post(
            identifier: "pro.mclean.health-check",
            title: "MClean Pro — Health Check",
            body: Self.body(for: summary)
        )
        return true
    }

    private static func body(for summary: HealthCheckSummary) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let sizeText = formatter.string(fromByteCount: summary.totalReclaimableBytes)
        return "Found \(summary.itemCount) items you could reclaim (\(sizeText))."
    }
}
