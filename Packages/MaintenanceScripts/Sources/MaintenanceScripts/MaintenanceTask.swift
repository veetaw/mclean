import Foundation

/// The result of actually running a `MaintenanceTask`.
///
/// Always constructed from a `MaintenanceCommandOutcome` (or a small,
/// fixed sequence of them) — never thrown — so one task's failure (missing
/// binary, non-zero exit, timeout) can never propagate as an error that
/// takes down a caller iterating over several tasks.
public struct MaintenanceTaskResult: Sendable, Equatable {
    public enum Outcome: Sendable, Equatable {
        case success
        case failure
    }

    public let taskID: String
    public let outcome: Outcome
    /// One-line, human-readable summary suitable for a UI toast/status row.
    public let summary: String
    /// Raw combined stdout/stderr from the underlying command(s), for a
    /// "show details" disclosure — never required reading to understand the
    /// `summary`.
    public let output: String

    public init(taskID: String, outcome: Outcome, summary: String, output: String) {
        self.taskID = taskID
        self.outcome = outcome
        self.summary = summary
        self.output = output
    }
}

/// One fixed, reviewed maintenance action — flush DNS, rebuild the Spotlight
/// index, verify the startup disk, or clear the font cache. See
/// `MaintenanceScriptsRegistry.all()` for the full list.
///
/// ## Why this doesn't go through `SafetyRules`/quarantine
///
/// Every other destructive-adjacent path in this app (detector findings,
/// `RemoteControlServer` approvals, `Shredder`) is either "delete this
/// specific file the user didn't choose the path of" or "irreversibly
/// destroy this specific file's content" — both need a denylist and,
/// usually, reversible quarantine, because the *target* is arbitrary,
/// scan-discovered, user-machine-specific data.
///
/// A `MaintenanceTask` is a different shape of thing entirely: it is
/// **action-invocation with a fixed, reviewed command set**, not free-form
/// file deletion. There is no "path" to classify, no user file that could
/// be wrongly destroyed — `dscacheutil -flushcache`, `killall -HUP
/// mDNSResponder`, `mdutil -E /`, `diskutil verifyVolume /`, and `atsutil
/// databases -remove` are exactly five fixed, hardcoded, human-reviewed
/// commands, none of which ever takes a caller-supplied path or string
/// argument. The safety property here isn't "check every target against a
/// denylist" — it's "only ever invoke these exact commands, spelled out at
/// compile time, and only when a human explicitly taps a button that shows
/// them the description first." `SafetyRules`' model (classify an arbitrary
/// discovered path, quarantine it reversibly) doesn't apply because there's
/// no arbitrary path in this picture at all.
///
/// ## Explicit, described, never automatic
///
/// Every conforming type's `description` is meant to be shown to the user
/// **before** they can trigger `run(using:)` — mirroring
/// `DevToolsDetectors.DevToolsGuidedAction`'s "describe the action, let the
/// user decide" pattern, just with this package actually able to invoke the
/// command itself (unlike a `DevToolsGuidedAction`, which is purely
/// descriptive data the user runs in their own shell). Nothing in this
/// package ever calls `run(using:)` on its own — that only ever happens
/// from an explicit user tap in `MainAppUI`.
public protocol MaintenanceTask: Sendable, Identifiable {
    var id: String { get }
    var title: String { get }
    /// Exactly what this task does, in plain language, including whether it
    /// will prompt for an administrator password and any caveat about when
    /// the effect fully takes hold (e.g. "may need a logout to fully apply").
    /// The UI must show this before the user can trigger `run(using:)`.
    var description: String { get }
    /// Whether invoking this task shows the user macOS's own admin-password/
    /// Touch ID elevation dialog. `false` for every task except rebuilding
    /// the Spotlight index.
    var requiresAdministratorPrivileges: Bool { get }

    /// Actually performs the action. Only ever called from an explicit user
    /// tap in the real UI — never automatically, never on app launch, never
    /// as a side effect of a scan.
    ///
    /// - Parameter runner: the command runner to use. Production call sites
    ///   should pass `LiveMaintenanceCommandRunner()` (or rely on the
    ///   `run()` convenience below, which does that for you); tests inject a
    ///   fake so no real process is ever launched.
    func run(using runner: MaintenanceCommandRunning) async -> MaintenanceTaskResult
}

extension MaintenanceTask {
    /// Convenience for real call sites: runs the task against the real
    /// system via `LiveMaintenanceCommandRunner`.
    public func run() async -> MaintenanceTaskResult {
        await run(using: LiveMaintenanceCommandRunner())
    }
}

/// Per-command timeout used by every `MaintenanceTask`. Generous enough for
/// a real command (including the human interaction time an admin-privileges
/// prompt needs) while still guaranteeing a hung or blocked subprocess can
/// never hang the caller forever.
///
/// The Spotlight elevation case is the one task where a human is expected to
/// pause at a system password dialog; 120s comfortably covers that without
/// leaving every other, near-instant command waiting anywhere near as long
/// on a genuine hang.
let maintenanceCommandTimeout: TimeInterval = 120
