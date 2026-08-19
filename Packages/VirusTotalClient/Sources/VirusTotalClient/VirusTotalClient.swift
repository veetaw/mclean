import Foundation

/// Client for the VirusTotal v3 API. Default behavior is hash-check only
/// (PROMPT MASTER §5.7): SHA-256 lookup against `/api/v3/files/{id}`, never
/// an upload, unless the caller explicitly opts in per-file via
/// `uploadFile(consentGiven: true, ...)`.
public protocol VirusTotalClient: Sendable {
    /// Looks up a file by its SHA-256 hash. Never transmits file contents.
    /// Returns `nil` if VirusTotal has no record for this hash (not
    /// necessarily "clean" — just "unknown").
    func lookupHash(_ sha256: String) async throws -> VirusTotalReport?

    /// Uploads the full file contents for scanning. MUST NOT be called
    /// without explicit, per-file user consent obtained by the caller —
    /// this method itself has no way to enforce that, so call sites are
    /// responsible for gating it behind a confirmation UI.
    func uploadFile(at path: String, consentGiven: Bool) async throws -> VirusTotalReport

    /// Whether the client currently has a usable API key configured. UI
    /// should show VT features as visible-but-disabled (not hidden) when
    /// this is false, with an explanation — see PROMPT MASTER §5.7.
    var isConfigured: Bool { get }
}

public struct VirusTotalReport: Sendable, Hashable, Codable {
    public let sha256: String
    public let maliciousCount: Int
    public let suspiciousCount: Int
    public let harmlessCount: Int
    public let undetectedCount: Int
    public let permalink: URL?
}

/// Enforces VirusTotal's public-tier rate limits (4 req/min, 500/day) with
/// queuing + backoff. No silent bulk requests: callers get a queued-position
/// signal rather than the client firing requests unattended in the
/// background across many files.
///
/// `awaitSlot()` genuinely suspends (via the injected `Sleeping`) when the
/// per-minute or per-day budget is exhausted, waking up only once the
/// relevant window has reset -- it never spins or retries aggressively, and
/// it never lets a request through while over budget. `clock`/`sleeper` are
/// injectable so tests can exercise this wait behavior with a fake clock
/// instead of blocking on real minutes/days.
public actor VirusTotalRateLimiter {
    public struct Limits: Sendable {
        public var requestsPerMinute: Int
        public var requestsPerDay: Int

        public static let freeTier = Limits(requestsPerMinute: 4, requestsPerDay: 500)
    }

    private let limits: Limits
    private let clock: Clock
    private let sleeper: Sleeping
    private var minuteWindowStart: Date
    private var requestsThisMinute: Int = 0
    private var dayWindowStart: Date
    private var requestsToday: Int = 0

    public init(
        limits: Limits = .freeTier,
        clock: Clock = SystemClock(),
        sleeper: Sleeping = TaskSleeper()
    ) {
        self.limits = limits
        self.clock = clock
        self.sleeper = sleeper
        let start = clock.now()
        self.minuteWindowStart = start
        self.dayWindowStart = start
    }

    /// Suspends until it is safe to make one more request, then reserves the
    /// slot before returning. If the per-minute budget is exhausted, waits
    /// only until that minute window resets; if the per-day budget is
    /// exhausted, waits until the day window resets. Either way this is a
    /// single bounded wait per exhausted window (re-checked in a loop, since
    /// time may have been injected non-monotonically in tests, or a wait
    /// could wake slightly early) -- not a retry/spin loop hammering the
    /// clock. Throws `CancellationError` promptly if the calling task is
    /// cancelled while waiting, instead of waiting the full duration out.
    public func awaitSlot() async throws {
        while true {
            try Task.checkCancellation()
            let current = clock.now()
            resetWindowsIfNeeded(current: current)

            if requestsToday >= limits.requestsPerDay {
                let wait = max(1, 86400 - current.timeIntervalSince(dayWindowStart))
                await sleeper.sleep(for: wait)
                try Task.checkCancellation()
                continue
            }
            if requestsThisMinute >= limits.requestsPerMinute {
                let wait = max(1, 60 - current.timeIntervalSince(minuteWindowStart))
                await sleeper.sleep(for: wait)
                try Task.checkCancellation()
                continue
            }

            requestsThisMinute += 1
            requestsToday += 1
            return
        }
    }

    private func resetWindowsIfNeeded(current: Date) {
        if current.timeIntervalSince(minuteWindowStart) >= 60 {
            minuteWindowStart = current
            requestsThisMinute = 0
        }
        if current.timeIntervalSince(dayWindowStart) >= 86400 {
            dayWindowStart = current
            requestsToday = 0
        }
    }

    public func remainingToday() -> Int {
        max(0, limits.requestsPerDay - requestsToday)
    }
}
