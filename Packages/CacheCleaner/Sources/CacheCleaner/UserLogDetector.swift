import Foundation
import CoreScanEngine

/// Flags stale entries directly under `~/Library/Logs/*` — user-writable
/// per-app logs, no elevated permissions required.
///
/// Deliberately does **not** attempt `/var/log` or any other root-owned
/// system log location: those require privileged filesystem access this app
/// doesn't have yet (no `PrivilegedHelper` executable exists — see
/// `ARCHITECTURE.md`'s module graph and status table). Extending coverage to
/// system-wide logs is a documented future extension once a privileged
/// helper exists to read them safely; this detector never attempts it and
/// never silently swallows a permission failure as if it had succeeded — an
/// unreadable path is simply skipped (see `CacheCleanerFS`).
///
/// An entry is only flagged when the *latest modification found anywhere
/// inside it* (not just its own top-level mtime) is older than
/// `staleAgeThreshold`, so an actively-appended-to log inside an
/// otherwise-old-looking directory is never wrongly flagged.
///
/// Strictly read-only. See `CoreScanEngine.Detector`.
public struct UserLogDetector: Detector {
    public let id = "junk.logs.user-logs"
    public let displayName = "App logs"
    public let category: DetectorCategory = .systemJunk

    private let staleAgeThreshold: TimeInterval
    private let now: @Sendable () -> Date

    public init(
        staleAgeThreshold: TimeInterval = 7 * 24 * 3600,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.staleAgeThreshold = staleAgeThreshold
        self.now = now
    }

    public func scan(context: ScanContext) async throws -> [ScanItem] {
        var items: [ScanItem] = []
        for home in CacheCleanerHomeDirectories.resolve(context) {
            if Task.isCancelled { break }
            items.append(contentsOf: scanLogs(home: home))
        }
        return items
    }

    private func scanLogs(home: String) -> [ScanItem] {
        let root = home + "/Library/Logs"
        guard CacheCleanerFS.isDirectory(root) else { return [] }

        var items: [ScanItem] = []
        for entry in CacheCleanerFS.directoryEntries(root) {
            if Task.isCancelled { break }
            guard !entry.hasPrefix(".") else { continue }
            let path = root + "/" + entry

            let (size, latest) = CacheCleanerFS.recursiveSizeAndLatestModification(
                of: path,
                isCancelled: { Task.isCancelled }
            )
            guard let latest, now().timeIntervalSince(latest) >= staleAgeThreshold else { continue }

            items.append(ScanItem(
                path: path,
                sizeBytes: size,
                sourceDetectorID: id,
                category: "App log — \(entry)",
                lastUsed: LastUsedEvidence(date: latest, source: .filesystemMTime),
                reason: "'\(entry)' under ~/Library/Logs, no activity anywhere in it for \(daysText(staleAgeThreshold)) (\(byteCountText(size))). Apps recreate their own log files/directories as needed; not a system log (~/Library/Logs only — root-owned /var/log is out of scope until a privileged helper exists)."
            ))
        }
        return items
    }
}
