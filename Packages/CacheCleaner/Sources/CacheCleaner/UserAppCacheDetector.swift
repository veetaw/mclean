import Foundation
import CoreScanEngine

/// Flags stale and/or large per-application cache directories directly under
/// `~/Library/Caches/*`.
///
/// Deliberately does **not** report every subdirectory unconditionally —
/// only ones with a plausible staleness signal, since dumping the whole
/// directory would just be "here is everything present", not a curated
/// cleanup candidate list. An entry is flagged when *either* nothing inside
/// it has been touched in `staleAgeThreshold`, *or* it's grown past
/// `largeSizeThreshold` — the reason text says which (or both).
///
/// Deliberately excludes subdirectories already owned by another detector
/// package in this repo, confirmed by reading their source before writing
/// this file (see `excludedTopLevelNames`) — re-reporting the same
/// directory under two different `sourceDetectorID`s would double-count
/// recoverable space and confuse the UI about which detector "owns" a path.
///
/// Strictly read-only. See `CoreScanEngine.Detector`.
public struct UserAppCacheDetector: Detector {
    public let id = "junk.cache.user-app-cache"
    public let displayName = "App caches"
    public let category: DetectorCategory = .systemJunk

    /// Top-level `~/Library/Caches` entry names already owned by another
    /// detector package — never re-reported here:
    /// - `pip`, `pypoetry` — `DevToolsDetectors.PythonDetector`
    /// - `go-build` — `DevToolsDetectors.GoDetector`
    /// - `Homebrew` — `DevToolsDetectors.HomebrewDetector`
    /// - `JetBrains` — `DevToolsDetectors.EditorDetector`
    /// - `Yarn` — `DevToolsDetectors.NodeDetector`
    /// - `fastlane` — `MobileDevDetectors.FastlaneCacheDetector`
    /// - `CocoaPods` — `MobileDevDetectors.CocoaPodsCacheDetector`
    /// - `Google` — `MobileDevDetectors.AndroidStudioCacheDetector` owns the
    ///   `AndroidStudio*` subdirectories inside `~/Library/Caches/Google`;
    ///   the whole `Google` entry is excluded here (rather than partially
    ///   drilling in around just the `AndroidStudio*` names) to keep one
    ///   directory tree from ever being split across two detector IDs.
    /// - `TemporaryItems` — behaves like a temp directory, not a regenerable
    ///   app cache; handled separately (and more conservatively, by latest
    ///   mtime found *anywhere inside*, not just its own) by
    ///   `TempFilesDetector` in this package.
    static let excludedTopLevelNames: Set<String> = [
        "pip", "pypoetry", "go-build", "Homebrew", "JetBrains", "Yarn",
        "fastlane", "CocoaPods", "Google", "TemporaryItems"
    ]

    private let staleAgeThreshold: TimeInterval
    private let largeSizeThreshold: Int64
    private let now: @Sendable () -> Date

    public init(
        staleAgeThreshold: TimeInterval = 14 * 24 * 3600,
        largeSizeThreshold: Int64 = 100 * 1024 * 1024,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.staleAgeThreshold = staleAgeThreshold
        self.largeSizeThreshold = largeSizeThreshold
        self.now = now
    }

    public func scan(context: ScanContext) async throws -> [ScanItem] {
        var items: [ScanItem] = []
        for home in CacheCleanerHomeDirectories.resolve(context) {
            if Task.isCancelled { break }
            items.append(contentsOf: scanCaches(home: home))
        }
        return items
    }

    private func scanCaches(home: String) -> [ScanItem] {
        let root = home + "/Library/Caches"
        guard CacheCleanerFS.isDirectory(root) else { return [] }

        var items: [ScanItem] = []
        for entry in CacheCleanerFS.directoryEntries(root) {
            if Task.isCancelled { break }
            guard !entry.hasPrefix("."), !Self.excludedTopLevelNames.contains(entry) else { continue }
            let path = root + "/" + entry
            guard CacheCleanerFS.isDirectory(path) else { continue }

            let (size, latest) = CacheCleanerFS.recursiveSizeAndLatestModification(
                of: path,
                isCancelled: { Task.isCancelled }
            )

            var reasons: [String] = []
            if let latest, now().timeIntervalSince(latest) >= staleAgeThreshold {
                reasons.append("nothing in it has been touched in \(daysText(staleAgeThreshold))")
            }
            if let size, size >= largeSizeThreshold {
                reasons.append("it's grown to \(byteCountText(size)), above the \(byteCountText(largeSizeThreshold)) threshold")
            }
            guard !reasons.isEmpty else { continue }

            items.append(ScanItem(
                path: path,
                sizeBytes: size,
                sourceDetectorID: id,
                category: "App cache — \(entry)",
                lastUsed: latest.map { LastUsedEvidence(date: $0, source: .filesystemMTime) },
                reason: "Cache directory for '\(entry)' under ~/Library/Caches: \(reasons.joined(separator: "; ")). App caches are normally regenerated automatically on demand; review before removing if this app relies on cached offline data."
            ))
        }
        return items
    }
}
