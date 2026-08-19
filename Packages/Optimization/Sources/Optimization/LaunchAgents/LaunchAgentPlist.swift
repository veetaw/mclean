import Foundation

/// A parsed macOS Launch Agent property list — the job description
/// `launchd` reads from `~/Library/LaunchAgents` or `/Library/LaunchAgents`
/// (see the `launchd.plist(5)` man page, a public/documented format; this
/// package reads these files exactly like any other unprivileged process
/// with read access to the directory — no private API involved).
///
/// Only the subset of keys this package acts on is modeled here;
/// unrecognized keys in the source plist are simply ignored.
public struct LaunchAgentPlist: Sendable, Hashable {
    /// Which of the two scopes this package scans this plist came from.
    /// Deliberately **not** including `/Library/LaunchDaemons` or
    /// `/System/Library/LaunchAgents` — both are root-owned/system-critical
    /// and out of scope for this build, which has no privileged helper yet
    /// (see this file's directory-level doc comment on `LaunchAgentDetector`).
    public enum Scope: String, Sendable, Hashable, Codable {
        /// `~/Library/LaunchAgents` — applies only to the current user,
        /// user-writable without elevation.
        case user
        /// `/Library/LaunchAgents` — applies to every user on the machine,
        /// but still writable by an admin without root/a privileged helper
        /// (unlike `/Library/LaunchDaemons`, which runs as root).
        case system
    }

    /// Absolute path to the `.plist` file on disk.
    public let path: String
    /// `Label` key — launchd's required unique job identifier. `nil` only
    /// for a plist that parses as a valid property list but is missing this
    /// (technically required) key.
    public let label: String?
    /// `Program`, or the first element of `ProgramArguments` when `Program`
    /// is absent — the executable this job launches, if determinable.
    public let program: String?
    /// `RunAtLoad` key. `true` means launchd starts this job every time the
    /// job definition is loaded, which for a Launch Agent under either
    /// scanned scope means, in practice, "at every login."
    public let runAtLoad: Bool
    /// `KeepAlive` key. `true` if the key is present as a bare `true`, *or*
    /// as a conditions dictionary (launchd supports both forms; this type
    /// only records whether *some* keep-alive behavior is configured, not
    /// which specific condition(s) — see `launchd.plist(5)` for the full
    /// dictionary form).
    public let keepAlive: Bool
    public let scope: Scope

    public init(
        path: String,
        label: String?,
        program: String?,
        runAtLoad: Bool,
        keepAlive: Bool,
        scope: Scope
    ) {
        self.path = path
        self.label = label
        self.program = program
        self.runAtLoad = runAtLoad
        self.keepAlive = keepAlive
        self.scope = scope
    }
}
