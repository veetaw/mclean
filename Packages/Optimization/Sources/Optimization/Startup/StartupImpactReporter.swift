import Foundation

/// One Launch Agent flagged as a "candidate that may affect startup time."
///
/// This is deliberately **not** a measured timing report. Nothing in this
/// package (or this build) has real boot/login timing telemetry — that
/// would require elevated permissions or kernel-level instrumentation this
/// app doesn't have (no privileged helper is scaffolded yet; see
/// `LaunchAgentDetector`'s doc comment). `runsAtLoad`/`keepsAlive` are the
/// two `launchd.plist(5)` keys that *correlate* with "this runs at every
/// login/boot" — nothing more precise than that.
public struct StartupImpactCandidate: Sendable, Hashable {
    public let plist: LaunchAgentPlist
    /// Mirrors `plist.runAtLoad` — starts automatically when loaded, which
    /// in practice means every login for an item under either scanned
    /// Launch Agent location.
    public let runsAtLoad: Bool
    /// Mirrors `plist.keepAlive` — launchd relaunches it if it exits, so it
    /// keeps a persistent presence across the session rather than running
    /// once and quitting.
    public let keepsAlive: Bool

    public init(plist: LaunchAgentPlist, runsAtLoad: Bool, keepsAlive: Bool) {
        self.plist = plist
        self.runsAtLoad = runsAtLoad
        self.keepsAlive = keepsAlive
    }
}

/// Best-effort, explicitly-approximate "processes that may slow down
/// startup" reporter — PROMPT MASTER §5.1's "elenco processi che
/// rallentano l'avvio."
///
/// ## Honest scope
///
/// This app cannot get real historical boot-time telemetry (per-process
/// wall-clock contribution to login/boot duration) without elevated
/// permissions or a kernel extension, neither of which exist in this
/// build. Rather than fabricate precision it doesn't have, this type only
/// ever reports **static correlates**: whether a discovered Launch Agent
/// has `RunAtLoad: true` and/or `KeepAlive` configured — both plist keys
/// that describe "this runs at every login/boot," not how long it took to
/// do so. There is no ranking, scoring, or "this one is slow" claim
/// anywhere in this type; callers/UI copy referencing this data must keep
/// describing it as candidates, never as a measured result.
public struct StartupImpactReporter: Sendable {
    public init() {}

    /// Filters `plists` down to the ones that run at load and/or keep
    /// themselves alive — the two static signals this build can honestly
    /// surface as "may affect startup time."
    public func candidates(from plists: [LaunchAgentPlist]) -> [StartupImpactCandidate] {
        plists
            .filter { $0.runAtLoad || $0.keepAlive }
            .map { StartupImpactCandidate(plist: $0, runsAtLoad: $0.runAtLoad, keepsAlive: $0.keepAlive) }
    }

    /// Convenience: discovers and parses every Launch Agent plist under the
    /// two locations `LaunchAgentDetector` scans, then reduces them to
    /// startup-impact candidates. Read-only; never throws — an unreadable
    /// location just contributes no candidates.
    public func report(
        userLaunchAgentsPath: String = NSHomeDirectory() + "/Library/LaunchAgents",
        systemLaunchAgentsPath: String = "/Library/LaunchAgents",
        fileManager: FileManager = .default
    ) -> [StartupImpactCandidate] {
        let userPlists = LaunchAgentPlistParser.discoverAndParse(
            in: userLaunchAgentsPath,
            scope: .user,
            fileManager: fileManager
        )
        let systemPlists = LaunchAgentPlistParser.discoverAndParse(
            in: systemLaunchAgentsPath,
            scope: .system,
            fileManager: fileManager
        )
        return candidates(from: userPlists + systemPlists)
    }
}
