import Foundation
#if canImport(ServiceManagement)
import ServiceManagement
#endif

/// A `RunAtLoad`-style Launch Agent, surfaced as a best-effort "looks like
/// a login item" candidate. See `LoginItemsInspector`'s doc comment for
/// exactly what this coverage does and does not represent.
public struct LoginItemCandidate: Sendable, Hashable {
    public let plist: LaunchAgentPlist

    public init(plist: LaunchAgentPlist) {
        self.plist = plist
    }
}

/// Read-only, honest-about-its-limits login items inspector.
///
/// ## What "complete login items coverage" would require, and why this
/// type doesn't claim it
///
/// Apple does not expose a public API that lists *every* login item
/// registered by *every* app the way System Settings' own "General >
/// Login Items" UI can — that UI has privileged access to
/// `backgroundtaskmanagementd`'s registration database
/// (`~/Library/Application Support/com.apple.backgroundtaskmanagementagent`
/// and related private frameworks), which third-party processes cannot
/// read without either:
///
/// - **Full Disk Access**, and even then there is no documented, stable
///   public format for that database to parse — it would mean depending on
///   a private, undocumented store that can change across macOS releases; or
/// - System Settings' own **private** `BackgroundTaskManagement` framework
///   API, which this package is explicitly forbidden from using (no
///   private/undocumented API — see this package's task constraints).
///
/// What genuinely **is** achievable from an unprivileged process, and what
/// this type implements:
///
/// 1. **This app's own registration status** — `mainAppStatus()`, via the
///    public `SMAppService.mainApp.status` API. Exact and authoritative,
///    but only for this one app.
/// 2. **Best-effort candidates from `~/Library/LaunchAgents`** —
///    `bestEffortUserLoginItemCandidates()` looks for plists with
///    `RunAtLoad: true`, the closest unprivileged approximation of "this
///    behaves like a login item." This is a heuristic, not ground truth:
///    it will miss login items registered purely through `SMAppService`
///    (which don't necessarily drop a plist under `LaunchAgents` at all —
///    modern `SMAppService.register()` items are tracked by
///    `backgroundtaskmanagementd` instead), and it may include Launch
///    Agents that aren't really "apps that open at login" in the System
///    Settings sense (background helpers, sync daemons, etc).
/// 3. **An optional AppleScript supplement** —
///    `appleScriptSupplementalNames()`, via `AppleScriptLoginItemsQuery`
///    (System Events' public, documented login items list). Only reflects
///    the classic Login Items mechanism, requires Automation permission,
///    and degrades to `nil` on any failure — never thrown, never crashes.
///
/// Strictly read-only: nothing here registers, unregisters, enables, or
/// disables anything.
public struct LoginItemsInspector: Sendable {
    private let appleScriptQuery: AppleScriptLoginItemsQuery

    public init() {
        self.appleScriptQuery = AppleScriptLoginItemsQuery()
    }

    /// This app's own login-item registration status, via the only public,
    /// documented API for this: `SMAppService.mainApp.status`.
    #if canImport(ServiceManagement)
    @available(macOS 13.0, *)
    public func mainAppStatus() -> LoginItemStatus {
        LoginItemStatus(SMAppService.mainApp.status)
    }
    #endif

    /// Best-effort candidates: plists directly under `launchAgentsPath`
    /// (defaults to `~/Library/LaunchAgents` — deliberately never
    /// `/Library/LaunchAgents`, which is shared across every account and
    /// isn't "this user's login items") whose `RunAtLoad` is `true`.
    ///
    /// See this type's doc comment for exactly what this coverage does and
    /// does not represent. Never throws; an unreadable directory just
    /// yields `[]`.
    public func bestEffortUserLoginItemCandidates(
        launchAgentsPath: String = NSHomeDirectory() + "/Library/LaunchAgents",
        fileManager: FileManager = .default
    ) -> [LoginItemCandidate] {
        LaunchAgentPlistParser.discoverAndParse(in: launchAgentsPath, scope: .user, fileManager: fileManager)
            .filter(\.runAtLoad)
            .map(LoginItemCandidate.init)
    }

    /// Optional supplement: the names System Events reports as classic
    /// Login Items, via AppleScript. `nil` if the query fails for any
    /// reason (see `AppleScriptLoginItemsQuery`) — callers should treat
    /// `nil` as "unavailable," never as "user has no login items."
    public func appleScriptSupplementalNames() async -> [String]? {
        await appleScriptQuery.queryLoginItemNames()
    }
}
