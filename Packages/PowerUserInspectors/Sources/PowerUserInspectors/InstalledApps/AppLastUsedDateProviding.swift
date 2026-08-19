import Foundation

/// Best-effort "when was this app last used" signal for
/// `InstalledAppsInspector`. There is no public API that answers this
/// directly and reliably; the strongest generally-available signal is
/// Spotlight's `kMDItemLastUsedDate` attribute, read here via the read-only
/// `mdls` CLI (see `MDLSLastUsedDateProvider`) rather than `NSMetadataQuery`,
/// which is asynchronous/notification-driven and awkward to bound with a
/// hard timeout the way a subprocess call is.
///
/// Kept as a protocol so:
/// - tests can inject a fixed/nil answer instead of depending on the test
///   machine's real Spotlight index (which never indexes a temp directory
///   fixture anyway);
/// - a sandboxed build (where `mdls` may not reflect another app's usage,
///   or shelling out is undesirable) can swap in `NullAppLastUsedDateProvider`
///   without changing `InstalledAppsInspector` itself.
public protocol AppLastUsedDateProviding: Sendable {
    /// Returns Spotlight's last-used date for the bundle at `path`, or `nil`
    /// if unavailable for any reason (never throws).
    func lastUsedDate(forBundlePath path: String) async -> Date?
}

/// Real implementation, backed by `/usr/bin/mdls -name kMDItemLastUsedDate
/// -raw <path>` — a read-only Spotlight metadata query, bounded by a
/// timeout, matching every other subprocess call in this package.
public struct MDLSLastUsedDateProvider: AppLastUsedDateProviding {
    private let commandRunner: ExternalCommandRunning
    private let mdlsPath: String
    private let timeout: TimeInterval

    public init(mdlsPath: String = "/usr/bin/mdls", timeout: TimeInterval = 5) {
        self.commandRunner = RealExternalCommandRunner()
        self.mdlsPath = mdlsPath
        self.timeout = timeout
    }

    init(commandRunner: ExternalCommandRunning, mdlsPath: String = "/usr/bin/mdls", timeout: TimeInterval = 5) {
        self.commandRunner = commandRunner
        self.mdlsPath = mdlsPath
        self.timeout = timeout
    }

    public func lastUsedDate(forBundlePath path: String) async -> Date? {
        guard let result = await commandRunner.run(
            executable: mdlsPath,
            arguments: ["-name", "kMDItemLastUsedDate", "-raw", path],
            currentDirectory: nil,
            timeout: timeout
        ) else { return nil }
        return Self.parseMDLSDate(result.standardOutput)
    }

    /// `mdls -raw` prints either `(null)` (attribute not set) or a date
    /// formatted like `2024-05-01 12:34:56 +0000`.
    static func parseMDLSDate(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "(null)" else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: trimmed)
    }
}

/// Always returns `nil`. Useful as the injected provider in tests (a temp
/// directory `.app` fixture is never Spotlight-indexed, so a real
/// `mdls` call would just return `(null)` anyway — this skips the
/// subprocess entirely) and as an explicit "don't bother" choice at call
/// sites that don't want the extra process launch per app.
public struct NullAppLastUsedDateProvider: AppLastUsedDateProviding {
    public init() {}
    public func lastUsedDate(forBundlePath path: String) async -> Date? { nil }
}
