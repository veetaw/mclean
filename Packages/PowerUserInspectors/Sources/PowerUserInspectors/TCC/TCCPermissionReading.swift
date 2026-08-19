import Foundation

/// Reads a best-effort view of TCC ("Privacy & Security") grants recorded
/// on this Mac.
///
/// **Why this is best-effort, not authoritative**: macOS does not expose a
/// public, sandboxable API for one app to read another app's TCC grants.
/// The only route available to a non-sandboxed (Developer ID) build is
/// reading `~/Library/Application Support/com.apple.TCC/TCC.db` directly —
/// an undocumented, private SQLite schema that has changed across macOS
/// releases and requires this process to already hold Full Disk Access
/// (macOS enforces that at the file-permission level; there's no way around
/// it, and there shouldn't be). None of that is guaranteed to keep working
/// on a future macOS release. Every conforming type must:
///
/// - never throw — a read that fails for any reason returns
///   `.unavailable(reason:)`, not an error, so callers can show honest
///   "permission data unavailable" UI rather than crash or silently show
///   nothing;
/// - never write to the database, obviously — this is a read path only.
///
/// **This protocol intentionally has no revoke/write capability of any
/// kind.** macOS does not allow a third-party app to programmatically
/// revoke another app's TCC grant ("macOS non permette revoca
/// programmatica diretta" — product spec). The only supported way to change
/// a grant from this app is `TCCSettingsPaneOpener`, which opens System
/// Settings to the right pane so the *user* flips it themselves. Keeping
/// read and "open settings" as two entirely separate, narrowly-named types
/// (rather than one type with a `revoke()` method that happens to be
/// unimplemented) makes the absence of programmatic revocation structural,
/// not just documented.
public protocol TCCPermissionReading: Sendable {
    /// Reads grants for `clientIdentifier` (a bundle ID or absolute tool
    /// path), or every grant in the database if `nil`.
    func readGrants(forClientIdentifier clientIdentifier: String?) async -> TCCReadResult
}
