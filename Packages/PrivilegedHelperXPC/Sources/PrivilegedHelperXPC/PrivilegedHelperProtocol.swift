import Foundation

/// Typed XPC contract between the main app (Developer ID target only — this
/// helper is never installed by the App Store build) and the privileged
/// helper registered via `SMAppService.daemon(plistName:)`.
///
/// Every method is a narrow, auditable capability rather than a generic
/// "run this command as root" escape hatch — the helper should refuse
/// anything not modeled explicitly here. All destructive-adjacent methods
/// still funnel through `SafetyRules` classification on the *app* side
/// before ever being requested; the helper does not re-implement that
/// policy, it only trusts a `SafetyVerdict` that accompanies the request
/// (see `PrivilegedOperationRequest`).
@objc public protocol PrivilegedHelperProtocol {
    /// Returns the helper's own version string, for the app to detect a
    /// stale installed helper and prompt for reinstall via `SMAppService`.
    func helperVersion(reply: @escaping (String) -> Void)

    /// Moves a path into the app's quarantine area on behalf of a user who
    /// doesn't own the file (e.g. cleaning another local user's cache dirs).
    /// The helper independently re-checks the hardcoded denylist server-side
    /// — it must never trust the app's classification alone, since a
    /// compromised or buggy app process is exactly the threat this
    /// separation defends against.
    func quarantinePath(
        _ path: String,
        requestID: String,
        reply: @escaping (_ success: Bool, _ errorDescription: String?) -> Void
    )

    /// Restores a previously quarantined path back to its original location.
    func restorePath(
        quarantineReceiptID: String,
        reply: @escaping (_ success: Bool, _ errorDescription: String?) -> Void
    )

    /// Runs one of a fixed set of known-safe maintenance scripts (flush DNS,
    /// rebuild Spotlight index, ...) identified by ID — never an arbitrary
    /// shell string supplied by the app.
    func runMaintenanceTask(
        _ taskID: String,
        reply: @escaping (_ success: Bool, _ output: String, _ errorDescription: String?) -> Void
    )
}

/// Well-known XPC Mach service name for the helper, shared by both the app
/// and the helper's own `main.swift` / launchd plist.
public enum PrivilegedHelperConstants {
    /// TODO(checkpoint): confirm final bundle identifier / team prefix
    /// before this is baked into a signed, notarized helper.
    public static let machServiceName = "com.mcleanpro.PrivilegedHelper"
}
