import Foundation

/// Centralized, runtime feature-flag registry computed once from
/// `BuildFlavor`. Every part of the app that needs to know "is X available
/// in this build" reads a `Capabilities` property instead of checking
/// `BuildFlavor`/`#if APPSTORE` itself — this is what keeps the App
/// Store/Developer ID split to one decision point (PROMPT MASTER §3).
///
/// The flags below are an honest inference from what's actually
/// sandbox-incompatible today:
///
/// - The macOS App Sandbox forbids installing/talking to a privileged
///   `SMAppService` daemon outside the app's own container in the way
///   `PrivilegedHelperXPC` is modeled (a system-wide Mach service) —
///   `canInstallPrivilegedHelper` is `false` in the App Store flavor.
/// - A sandboxed app cannot bind a listening socket reachable from other
///   devices on the LAN the way `RemoteControlServer` needs
///   (`com.apple.security.network.server` is technically grantable, but
///   combined with Bonjour advertisement + arbitrary inbound LAN
///   connections this is the kind of "server" App Review routinely rejects
///   for a utility app, and it cannot reach files outside the sandbox
///   container to serve real findings) — `canRunRemoteControlServer` is
///   `false` in the App Store flavor. See `AppEnvironment` for where this
///   gates server construction.
/// - Sandbox file access is scoped to user-selected files/folders
///   (security-scoped bookmarks) — there is no ambient "scan my whole
///   home directory and /Library" the way the Developer ID build does —
///   `canAccessOtherUsersFiles` and unrestricted filesystem scanning are
///   `false`.
/// - `Shredder` (Phase 5) does raw POSIX `open`/`write`/`ftruncate` on a
///   resolved absolute path, not through a persisted security-scoped
///   bookmark — this hasn't been verified to behave correctly under the
///   App Sandbox (a `.fileImporter`-granted URL's sandbox access and a raw
///   path string handed to POSIX syscalls are not obviously the same
///   thing), so `canRunShredder` stays Developer-ID-only until that's
///   actually confirmed, matching the product spec's Developer-ID-only
///   framing for a raw-file-I/O feature like this.
/// - Reading another app's TCC grants (`PowerUserInspectors.TCCDatabaseReader`)
///   requires Full Disk Access to a file outside the sandbox container
///   entirely (`~/Library/Application Support/com.apple.TCC/TCC.db`) — not
///   obtainable by a sandboxed app at all — `canReadTCCDatabase` is `false`
///   in the App Store flavor.
public struct Capabilities: Sendable, Hashable {
    public let flavor: BuildFlavor

    /// SMAppService-registered privileged helper (`PrivilegedHelperXPC`).
    public let canInstallPrivilegedHelper: Bool
    /// The LAN HTTP + Bonjour server (`RemoteControlServer`).
    public let canRunRemoteControlServer: Bool
    /// Ambient, unrestricted filesystem scanning (other users' home
    /// directories, arbitrary system paths) as opposed to user-selected
    /// files/folders granted through the sandbox.
    public let canAccessOtherUsersFiles: Bool
    /// Multi-pass secure-delete (`Shredder`, Phase 5). Developer-ID-only —
    /// see the type doc above for why.
    public let canRunShredder: Bool
    /// Reading `TCC.db` directly (`PowerUserInspectors.TCCDatabaseReader`).
    public let canReadTCCDatabase: Bool
    /// Registering as a background/menu-bar agent that runs independent of
    /// the main window (`MenuBarAgent`). Allowed in both flavors — a status
    /// item + scheduled scan of the sandbox container is sandbox-legal.
    public let canRunMenuBarAgent: Bool
    /// VirusTotal hash-check network calls. Allowed in both flavors — this
    /// is outbound `client` networking only (`com.apple.security.network.client`),
    /// which the App Store entitlements grant; see `App/project.yml`.
    public let canUseVirusTotalHashCheck: Bool

    public init(flavor: BuildFlavor) {
        self.flavor = flavor
        switch flavor {
        case .appStore:
            self.canInstallPrivilegedHelper = false
            self.canRunRemoteControlServer = false
            self.canAccessOtherUsersFiles = false
            self.canRunShredder = false
            self.canReadTCCDatabase = false
            self.canRunMenuBarAgent = true
            self.canUseVirusTotalHashCheck = true
        case .developerID:
            self.canInstallPrivilegedHelper = true
            self.canRunRemoteControlServer = true
            self.canAccessOtherUsersFiles = true
            self.canRunShredder = true
            self.canReadTCCDatabase = true
            self.canRunMenuBarAgent = true
            self.canUseVirusTotalHashCheck = true
        }
    }

    /// The capabilities for the flavor this binary was actually compiled
    /// as. This is the instance every call site should use in production
    /// code (`Capabilities.current.canRunRemoteControlServer`); the
    /// memberwise `init(flavor:)` above exists so tests can construct both
    /// flavors' flag sets without needing two separately-compiled binaries.
    public static let current = Capabilities(flavor: .current)
}

// MARK: - App Store receipt signal (nice-to-have, not load-bearing)

/// A secondary, purely informational signal for "does this binary look
/// like an App Store build" — **not** used to compute any `Capabilities`
/// flag above (those are 100% determined by the compile-time
/// `BuildFlavor`, which is authoritative and can't be spoofed by tampering
/// with a bundle after the fact the way a receipt check alone could be
/// relied upon for). A full StoreKit receipt validation (ASN.1 parsing,
/// Apple root CA chain verification, hash comparison against the device
/// GUID) is real work with real security properties to get right, and
/// isn't warranted for what is, at most, a diagnostic/telemetry footnote
/// here — so this is intentionally a stub.
public enum AppStoreReceiptSignal {
    /// Best-effort, placeholder check for the presence of an App Store
    /// receipt (`Bundle.main.appStoreReceiptURL`, mailbox pattern only).
    /// Does **not** validate the receipt's contents or signature — a
    /// missing/unreadable receipt only means "can't confirm", not "this
    /// is not an App Store build". Never gate a `Capabilities` flag on
    /// this; it exists purely so a future diagnostics/support screen has
    /// something to show, e.g. "Build flavor: App Store (receipt present)".
    public static func receipptIndicatesAppStoreBuild() -> Bool {
        guard let url = Bundle.main.appStoreReceiptURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }
}
