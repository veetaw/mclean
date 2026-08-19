import Foundation

/// Flushes macOS's DNS resolver cache.
///
/// Runs two fixed, well-known commands in sequence:
///
/// 1. `/usr/bin/dscacheutil -flushcache` — clears the Directory Service
///    cache, which includes cached DNS lookups.
/// 2. `/usr/bin/killall -HUP mDNSResponder` — sends `mDNSResponder` (the
///    system's DNS resolver daemon) a hangup signal, which makes it drop its
///    own internal cache and restart cleanly. This is the standard,
///    widely-documented way to fully flush DNS on modern macOS; either
///    command alone is not reliably sufficient.
///
/// Both are ordinary, unprivileged commands any logged-in user can run —
/// no `sudo`, no admin prompt, no elevation of any kind.
public struct FlushDNSCacheTask: MaintenanceTask {
    public let id = "maintenance.flush-dns"
    public let title = "Flush DNS Cache"
    public let description = """
    Clears macOS's cached DNS lookups so the next request for any hostname \
    is resolved fresh, instead of reusing a possibly stale or incorrect \
    cached address. Useful after changing networks, DNS servers, or when a \
    site seems to resolve to the wrong server. Runs \
    "dscacheutil -flushcache" followed by "killall -HUP mDNSResponder" — \
    both standard, safe commands that don't require an administrator \
    password. No files are touched.
    """
    public let requiresAdministratorPrivileges = false

    public init() {}

    public func run(using runner: MaintenanceCommandRunning) async -> MaintenanceTaskResult {
        let flush = await runner.run(
            executable: "/usr/bin/dscacheutil",
            arguments: ["-flushcache"],
            timeout: maintenanceCommandTimeout
        )
        guard flush.succeeded else {
            return MaintenanceTaskResult(
                taskID: id,
                outcome: .failure,
                summary: "dscacheutil -flushcache \(flush.failureDescription)",
                output: flush.combinedOutput
            )
        }

        let restart = await runner.run(
            executable: "/usr/bin/killall",
            arguments: ["-HUP", "mDNSResponder"],
            timeout: maintenanceCommandTimeout
        )
        guard restart.succeeded else {
            return MaintenanceTaskResult(
                taskID: id,
                outcome: .failure,
                summary: "killall -HUP mDNSResponder \(restart.failureDescription)",
                output: [flush.combinedOutput, restart.combinedOutput].filter { !$0.isEmpty }.joined(separator: "\n")
            )
        }

        return MaintenanceTaskResult(
            taskID: id,
            outcome: .success,
            summary: "DNS cache flushed.",
            output: [flush.combinedOutput, restart.combinedOutput].filter { !$0.isEmpty }.joined(separator: "\n")
        )
    }
}
