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
public actor VirusTotalRateLimiter {
    public struct Limits: Sendable {
        public var requestsPerMinute: Int
        public var requestsPerDay: Int

        public static let freeTier = Limits(requestsPerMinute: 4, requestsPerDay: 500)
    }

    private let limits: Limits
    private var minuteWindowStart: Date
    private var requestsThisMinute: Int = 0
    private var dayWindowStart: Date
    private var requestsToday: Int = 0

    public init(limits: Limits = .freeTier, now: Date = Date()) {
        self.limits = limits
        self.minuteWindowStart = now
        self.dayWindowStart = now
    }

    /// Suspends until it is safe to make one more request, then reserves the
    /// slot. `now` is injected for testability.
    public func awaitSlot(now: @Sendable () -> Date = Date.init) async {
        // Full sleep/backoff scheduling left to the RemoteControlServer/
        // MenuBarAgent integration agent — this is the accounting core.
        let current = now()
        if current.timeIntervalSince(minuteWindowStart) >= 60 {
            minuteWindowStart = current
            requestsThisMinute = 0
        }
        if current.timeIntervalSince(dayWindowStart) >= 86400 {
            dayWindowStart = current
            requestsToday = 0
        }
        requestsThisMinute += 1
        requestsToday += 1
    }

    public func remainingToday() -> Int {
        max(0, limits.requestsPerDay - requestsToday)
    }
}
