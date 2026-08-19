import Foundation

// MARK: - App-facing Swift-native abstraction

/// Swift-native, `async`/`await` abstraction over the helper's capabilities,
/// meant for app-side call sites to depend on instead of the `@objc`
/// `PrivilegedHelperProtocol` directly.
///
/// ## Why this exists instead of conforming a mock straight to
/// `PrivilegedHelperProtocol`
///
/// `PrivilegedHelperProtocol` is `@objc` with completion-handler ("reply")
/// parameters because that's what `NSXPCConnection`'s remote object proxy
/// requires on the wire, and `@objc` protocol conformance is realistically
/// restricted to `NSObject`-derived classes. That shape is the right one for
/// the actual cross-process boundary, but it's an awkward fit for app-side
/// Swift 6 strict-concurrency code, which wants `async`/`await`,
/// `Sendable` value types, and something that isn't tied to `NSObject`.
///
/// `PrivilegedHelperClientProtocol` is the app-facing seam: a plain Swift
/// `async` protocol exposing the same four operations, Swift-native. This
/// lets:
///   - `MockPrivilegedHelper` (below) implement it directly, as a plain
///     `actor`, entirely in-process — no XPC connection, no `SMAppService`,
///     no elevated privileges anywhere.
///   - A future real client wrap an `NSXPCConnection`'s
///     `remoteObjectProxyWithErrorHandler` (typed as
///     `PrivilegedHelperProtocol`) and adapt its reply closures into
///     `withCheckedContinuation`, conforming to this same
///     `PrivilegedHelperClientProtocol`.
///
/// App-side call sites should depend on `PrivilegedHelperClientProtocol`,
/// never directly on `PrivilegedHelperProtocol` or on
/// `MockPrivilegedHelper`'s concrete type, so the mock can be swapped for a
/// real XPC-backed implementation later with zero call-site changes — only
/// dependency injection at the composition root changes.
///
/// Each method here mirrors one `PrivilegedHelperProtocol` method 1:1 (same
/// name, same parameters, reply-closure payload turned into a return value).
public protocol PrivilegedHelperClientProtocol: Sendable {
    /// Mirrors `PrivilegedHelperProtocol.helperVersion(reply:)`.
    func helperVersion() async -> String

    /// Mirrors `PrivilegedHelperProtocol.quarantinePath(_:requestID:reply:)`.
    func quarantinePath(_ path: String, requestID: String) async -> PrivilegedHelperOperationResult

    /// Mirrors `PrivilegedHelperProtocol.restorePath(quarantineReceiptID:reply:)`.
    func restorePath(quarantineReceiptID: String) async -> PrivilegedHelperOperationResult

    /// Mirrors `PrivilegedHelperProtocol.runMaintenanceTask(_:reply:)`.
    func runMaintenanceTask(_ taskID: String) async -> PrivilegedHelperMaintenanceResult
}

/// Result of a quarantine or restore operation. Mirrors the
/// `(success: Bool, errorDescription: String?)` reply payload shared by
/// `quarantinePath` and `restorePath` on `PrivilegedHelperProtocol`.
public struct PrivilegedHelperOperationResult: Sendable, Equatable {
    public let success: Bool
    public let errorDescription: String?

    public init(success: Bool, errorDescription: String? = nil) {
        self.success = success
        self.errorDescription = errorDescription
    }
}

/// Result of a maintenance task run. Mirrors the
/// `(success: Bool, output: String, errorDescription: String?)` reply
/// payload of `runMaintenanceTask` on `PrivilegedHelperProtocol`.
public struct PrivilegedHelperMaintenanceResult: Sendable, Equatable {
    public let success: Bool
    public let output: String
    public let errorDescription: String?

    public init(success: Bool, output: String, errorDescription: String? = nil) {
        self.success = success
        self.output = output
        self.errorDescription = errorDescription
    }
}

// MARK: - Mock implementation

/// **Mock, in-memory simulation of a privileged helper. Not real elevation.**
///
/// `MockPrivilegedHelper` conforms to `PrivilegedHelperClientProtocol` so app
/// and UI code can be developed and tested against something with the real
/// interface's shape, without:
///   - any real `SMAppService` registration or lookup,
///   - any real XPC connection (`NSXPCConnection`, `NSXPCListener`, ...),
///   - any actual elevated file operation — "quarantining" a path here never
///     touches the file on disk at all, it only records the path in an
///     in-memory dictionary for this process's lifetime.
///
/// This type must never be mistaken for, or silently substituted as, the
/// real privileged helper in a shipping build. There is currently no real
/// implementation of `PrivilegedHelperClientProtocol` backed by XPC — see
/// `PrivilegedHelper/README.md` and
/// `Packages/PrivilegedHelperXPC/NOTES_FOR_ARCHITECTURE_DOC.md`.
///
/// ## Simulated semantics
///
/// - `helperVersion()` returns a fixed, obviously-mock version string.
/// - `quarantinePath(_:requestID:)` succeeds only when the path exists on
///   disk (as seen by the injected `FileManager`, no elevation used or
///   needed to check that) and doesn't fall under
///   `Self.forbiddenPathPrefixes` — a small, hardcoded list chosen only to
///   mirror the *spirit* of `SafetyRules.Denylist.forbiddenPathPrefixes`
///   closely enough that this mock never plausibly claims it would
///   quarantine something like `/System`. It intentionally does **not**
///   depend on the `SafetyRules` package — this package has no such
///   dependency and shouldn't gain one just for a mock's benefit; the real
///   helper is what must own that dependency and do the rigorous, canonical
///   re-check (see `FileSystemQuarantineManager` for the shape that real
///   check should eventually take on the app side, and the doc comment on
///   `PrivilegedHelperProtocol.quarantinePath` for why the helper itself
///   must never skip it).
///   On success, the path is recorded in memory keyed by `requestID` — this
///   mock treats the caller-supplied `requestID` as doubling as the
///   quarantine receipt ID, since `PrivilegedHelperProtocol` doesn't hand
///   back a separate identifier of its own in the reply.
/// - `restorePath(quarantineReceiptID:)` succeeds only for a receipt ID this
///   same mock instance actually recorded via a prior successful
///   `quarantinePath` call, and only once — restoring removes the in-memory
///   record, so restoring the same ID twice fails the second time, same as
///   a real receipt-consuming restore would.
/// - `runMaintenanceTask(_:)` recognizes a small fixed set of task IDs
///   (`Self.recognizedMaintenanceTaskIDs`) and returns a canned success with
///   placeholder output for those; any other task ID fails, mirroring the
///   real helper's documented refusal of anything not modeled explicitly.
///
/// An `actor` because a real XPC-backed client will field calls concurrently
/// from arbitrary app-side callers, and this mock should behave safely under
/// the same conditions rather than assume single-threaded use.
public actor MockPrivilegedHelper: PrivilegedHelperClientProtocol {
    /// Obviously-fake version string — never a real build/version number, so
    /// nobody mistakes this for output from an actually-installed helper.
    public static let mockHelperVersion = "0.0.0-mock-in-memory"

    /// Small, hardcoded set of path prefixes this mock refuses to
    /// "quarantine", chosen to mirror the spirit (not the full rigor) of
    /// `SafetyRules.Denylist.forbiddenPathPrefixes`. See the type doc for why
    /// this package doesn't just depend on `SafetyRules` instead.
    /// Note: listed in already-`standardizingPath`-normalized form, e.g.
    /// `/var/db` rather than `/private/var/db` — `NSString.standardizingPath`
    /// (used below, same as `SafetyRules.Denylist`) collapses that `/private`
    /// prefix away, so a literal `/private/var/db` entry here would silently
    /// never match anything.
    public static let forbiddenPathPrefixes: [String] = [
        "/System",
        "/var/db",
        "/Library/Keychains",
        "/dev",
    ]

    /// Fixed set of maintenance task IDs this mock recognizes as
    /// "known-safe". Anything else fails, mirroring the real helper's
    /// documented refusal to run arbitrary/unrecognized task IDs.
    public static let recognizedMaintenanceTaskIDs: Set<String> = [
        "flush-dns-cache",
        "rebuild-spotlight-index",
        "clear-launch-services-database",
    ]

    /// requestID -> original path, for paths this mock instance has
    /// "quarantined" and not yet restored.
    private var quarantinedPathsByReceiptID: [String: String] = [:]

    private let fileManager: FileManager

    /// - Parameter fileManager: only used to check whether a path exists
    ///   before pretending to quarantine it; never used to actually move,
    ///   delete, or otherwise modify anything. Injectable for tests.
    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func helperVersion() async -> String {
        Self.mockHelperVersion
    }

    public func quarantinePath(
        _ path: String,
        requestID: String
    ) async -> PrivilegedHelperOperationResult {
        let normalized = (path as NSString).standardizingPath

        if let reason = Self.forbiddenReason(forPath: normalized) {
            return PrivilegedHelperOperationResult(success: false, errorDescription: reason)
        }

        guard fileManager.fileExists(atPath: normalized) else {
            return PrivilegedHelperOperationResult(
                success: false,
                errorDescription: "No such file or directory: \(normalized)"
            )
        }

        // Simulated only: no actual move/copy happens. The path is simply
        // remembered against requestID so a later restorePath can plausibly
        // succeed or fail against what this mock actually "quarantined".
        quarantinedPathsByReceiptID[requestID] = normalized
        return PrivilegedHelperOperationResult(success: true)
    }

    public func restorePath(quarantineReceiptID: String) async -> PrivilegedHelperOperationResult {
        guard quarantinedPathsByReceiptID.removeValue(forKey: quarantineReceiptID) != nil else {
            return PrivilegedHelperOperationResult(
                success: false,
                errorDescription: "No quarantine receipt with id \(quarantineReceiptID)"
            )
        }
        return PrivilegedHelperOperationResult(success: true)
    }

    public func runMaintenanceTask(_ taskID: String) async -> PrivilegedHelperMaintenanceResult {
        guard Self.recognizedMaintenanceTaskIDs.contains(taskID) else {
            return PrivilegedHelperMaintenanceResult(
                success: false,
                output: "",
                errorDescription: "Unrecognized maintenance task id: \(taskID)"
            )
        }
        return PrivilegedHelperMaintenanceResult(
            success: true,
            output: "[mock] simulated run of \"\(taskID)\" — no real command was executed.",
            errorDescription: nil
        )
    }

    /// Test/debug hook: whether this mock currently considers `receiptID`
    /// quarantined. Not part of `PrivilegedHelperClientProtocol` — a real
    /// client wouldn't expose synchronous in-memory state like this.
    public func isQuarantined(receiptID: String) async -> Bool {
        quarantinedPathsByReceiptID[receiptID] != nil
    }

    /// Simplified stand-in for `SafetyRules.Denylist.forbiddenReason` —
    /// see the type doc comment for why this mock doesn't depend on
    /// `SafetyRules` for the real thing.
    private static func forbiddenReason(forPath path: String) -> String? {
        for prefix in forbiddenPathPrefixes where path == prefix || path.hasPrefix(prefix + "/") {
            return "Under protected system path \(prefix)."
        }
        return nil
    }
}
