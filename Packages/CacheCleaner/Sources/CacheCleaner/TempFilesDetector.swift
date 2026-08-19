import Foundation
import CoreScanEngine

/// Flags old, apparently-abandoned entries in per-user temp locations:
/// `NSTemporaryDirectory()` (macOS's per-user `/var/folders/.../T`
/// sandboxed temp directory) and `~/Library/Caches/TemporaryItems`.
///
/// Deliberately conservative: a temp directory can legitimately hold files
/// an active process is using *right now*, so entries are only flagged when
/// the *latest modification found anywhere inside them* — not just the
/// entry's own top-level mtime — is older than `staleAgeThreshold`. See
/// `CacheCleanerFS.recursiveSizeAndLatestModification`'s doc comment for why
/// that's the safer signal: a directory an active process is still writing
/// into will always have *something* inside it with a recent mtime, even if
/// the directory itself was created long ago.
///
/// Strictly read-only. See `CoreScanEngine.Detector`.
public struct TempFilesDetector: Detector {
    public let id = "junk.temp.temp-files"
    public let displayName = "Temporary files"
    public let category: DetectorCategory = .systemJunk

    private let staleAgeThreshold: TimeInterval
    private let systemTempDirectoryPath: String
    private let now: @Sendable () -> Date

    /// - Parameters:
    ///   - staleAgeThreshold: minimum "untouched anywhere inside" age before
    ///     an entry is flagged. Defaults to 3 days — deliberately several
    ///     days, not hours, since a `/tmp`-style directory legitimately
    ///     churns during normal use.
    ///   - systemTempDirectoryPath: defaults to `NSTemporaryDirectory()`.
    ///     Not home-relative, so — unlike this package's other detectors —
    ///     it isn't resolved from `ScanContext.roots`; tests override it
    ///     directly here (mirroring how `MobileDevDetectors`' path-based
    ///     detectors take an overridable root in their initializer) to
    ///     avoid ever touching the real system temp directory.
    public init(
        staleAgeThreshold: TimeInterval = 3 * 24 * 3600,
        systemTempDirectoryPath: String = NSTemporaryDirectory(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.staleAgeThreshold = staleAgeThreshold
        self.systemTempDirectoryPath = systemTempDirectoryPath
        self.now = now
    }

    public func scan(context: ScanContext) async throws -> [ScanItem] {
        var items: [ScanItem] = []
        items.append(contentsOf: scanDirectory(
            systemTempDirectoryPath,
            locationDescription: "the system temporary directory",
            sourceDetectorID: "junk.temp.system-temp-directory"
        ))
        if Task.isCancelled { return items }

        for home in CacheCleanerHomeDirectories.resolve(context) {
            if Task.isCancelled { break }
            items.append(contentsOf: scanDirectory(
                home + "/Library/Caches/TemporaryItems",
                locationDescription: "~/Library/Caches/TemporaryItems",
                sourceDetectorID: "junk.temp.temporary-items"
            ))
        }
        return items
    }

    private func scanDirectory(
        _ root: String,
        locationDescription: String,
        sourceDetectorID: String
    ) -> [ScanItem] {
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
                sourceDetectorID: sourceDetectorID,
                category: "Temporary file",
                lastUsed: LastUsedEvidence(date: latest, source: .filesystemMTime),
                reason: "'\(entry)' in \(locationDescription), nothing in it modified for \(daysText(staleAgeThreshold)) (\(byteCountText(size))) — looks abandoned rather than in use by an active process."
            ))
        }
        return items
    }
}
