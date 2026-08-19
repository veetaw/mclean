import Foundation

/// Clears macOS's font cache database.
///
/// Runs `atsutil databases -remove`, the standard command-line way to clear
/// the Apple Type Services font cache. Useful when fonts appear garbled,
/// missing, or a newly installed font doesn't show up in apps. No
/// administrator privileges are required.
///
/// The effect is not always immediate: macOS (and apps already running)
/// can keep font data cached in memory until the affected apps — or, for a
/// full effect, the Mac itself — restart. The description below says this
/// plainly rather than implying an instant fix.
public struct ClearFontCacheTask: MaintenanceTask {
    public let id = "maintenance.clear-font-cache"
    public let title = "Clear Font Cache"
    public let description = """
    Clears macOS's font cache by running "atsutil databases -remove". \
    Fixes garbled, missing, or duplicated fonts, and font substitution \
    issues. Doesn't require an administrator password. The cache is \
    rebuilt automatically as fonts are used again, but already-running \
    apps may keep showing the old cached font data until they're relaunched \
    — for a completely clean result you may need to log out and back in, \
    or restart.
    """
    public let requiresAdministratorPrivileges = false

    public init() {}

    public func run(using runner: MaintenanceCommandRunning) async -> MaintenanceTaskResult {
        let outcome = await runner.run(
            executable: "/usr/bin/atsutil",
            arguments: ["databases", "-remove"],
            timeout: maintenanceCommandTimeout
        )

        guard outcome.succeeded else {
            return MaintenanceTaskResult(
                taskID: id,
                outcome: .failure,
                summary: "atsutil databases -remove \(outcome.failureDescription)",
                output: outcome.combinedOutput
            )
        }

        return MaintenanceTaskResult(
            taskID: id,
            outcome: .success,
            summary: "Font cache cleared. Relaunch affected apps (or log out/restart) for a fully clean result.",
            output: outcome.combinedOutput
        )
    }
}
