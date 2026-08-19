import Foundation

/// Rebuilds the Spotlight index for the startup volume (`/`).
///
/// Runs `mdutil -E /`, which erases and schedules a full reindex of
/// Spotlight's metadata store for the given volume — the standard fix for
/// "Spotlight search returns nothing / stale results."
///
/// ## Why this goes through `osascript … with administrator privileges`
///
/// `mdutil -E` on the startup volume requires admin rights on modern macOS.
/// This app has **no privileged helper yet** (`PrivilegedHelperXPC` defines
/// only the XPC protocol so far — see `ARCHITECTURE.md`), so there is no
/// existing elevated channel to route this through. Two honest options
/// existed: silently fail/hide the feature until a helper exists, or use
/// macOS's own standard one-off elevation mechanism —
/// `osascript -e 'do shell script "…" with administrator privileges'` —
/// which pops the system's native password/Touch ID dialog, runs exactly
/// one fixed command with the user watching and explicitly consenting, and
/// then is done. It is **not** a persistent daemon, does not store or cache
/// credentials, and grants no standing privilege beyond this single
/// invocation. This is a genuinely useful feature and this is the
/// standard, transparent, Apple-documented way to get one-off elevation
/// from an app without a privileged helper — so it's implemented for real
/// rather than stubbed out.
///
/// The AppleScript string passed to `osascript -e` is a single fixed
/// literal, `do shell script "mdutil -E /" with administrator privileges` —
/// never built from any variable, argument, or external input. There is no
/// path from caller-supplied data to what gets elevated and run.
public struct RebuildSpotlightIndexTask: MaintenanceTask {
    public let id = "maintenance.rebuild-spotlight-index"
    public let title = "Rebuild Spotlight Index"
    public let description = """
    Erases and rebuilds the Spotlight search index for your startup disk. \
    Fixes Spotlight returning no results, stale results, or missing recent \
    files. Reindexing runs in the background afterward and can take a \
    while depending on how much is on your disk — search results may be \
    incomplete until it finishes. This requires administrator privileges: \
    macOS will show its standard password/Touch ID prompt once, for this \
    one command only — MClean Pro does not store your password or gain any \
    standing elevated access.
    """
    public let requiresAdministratorPrivileges = true

    public init() {}

    public func run(using runner: MaintenanceCommandRunning) async -> MaintenanceTaskResult {
        let outcome = await runner.run(
            executable: "/usr/bin/osascript",
            arguments: ["-e", "do shell script \"mdutil -E /\" with administrator privileges"],
            timeout: maintenanceCommandTimeout
        )

        guard outcome.succeeded else {
            // A non-zero exit here very commonly means the user cancelled
            // the password prompt — report that plainly rather than as a
            // scary generic failure, without assuming it from the exit code
            // alone (osascript doesn't guarantee a distinct code for it).
            return MaintenanceTaskResult(
                taskID: id,
                outcome: .failure,
                summary: "Spotlight reindex \(outcome.failureDescription). This can happen if the administrator prompt was cancelled.",
                output: outcome.combinedOutput
            )
        }

        return MaintenanceTaskResult(
            taskID: id,
            outcome: .success,
            summary: "Spotlight index rebuild started for the startup disk. Reindexing continues in the background.",
            output: outcome.combinedOutput
        )
    }
}
