import Foundation
import CoreScanEngine

/// Flags likely-abandoned incomplete downloads directly under `~/Downloads`:
/// files ending in `.download` (Safari), `.crdownload` (Chrome/Chromium), or
/// `.part` / `.partial` (Firefox and other Gecko-based browsers).
///
/// Deliberately conservative: only flags files whose own mtime is older than
/// `staleAgeThreshold` — a `.crdownload` from moments ago is very likely
/// still an active, in-progress download, not junk.
///
/// Strictly read-only. See `CoreScanEngine.Detector`.
public struct IncompleteDownloadDetector: Detector {
    public let id = "junk.downloads.incomplete"
    public let displayName = "Incomplete downloads"
    public let category: DetectorCategory = .systemJunk

    /// Well-known "download in progress" filename suffixes across Safari,
    /// Chrome/Chromium, and Firefox/other Gecko-based browsers.
    static let incompleteDownloadSuffixes: [String] = [".download", ".crdownload", ".part", ".partial"]

    private let staleAgeThreshold: TimeInterval
    private let now: @Sendable () -> Date

    public init(
        staleAgeThreshold: TimeInterval = 24 * 3600,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.staleAgeThreshold = staleAgeThreshold
        self.now = now
    }

    public func scan(context: ScanContext) async throws -> [ScanItem] {
        var items: [ScanItem] = []
        for home in CacheCleanerHomeDirectories.resolve(context) {
            if Task.isCancelled { break }
            items.append(contentsOf: scanDownloads(home: home))
        }
        return items
    }

    private func scanDownloads(home: String) -> [ScanItem] {
        let root = home + "/Downloads"
        guard CacheCleanerFS.isDirectory(root) else { return [] }

        var items: [ScanItem] = []
        for entry in CacheCleanerFS.directoryEntries(root) {
            if Task.isCancelled { break }
            let lowered = entry.lowercased()
            guard let suffix = Self.incompleteDownloadSuffixes.first(where: { lowered.hasSuffix($0) }) else { continue }
            let path = root + "/" + entry
            guard !CacheCleanerFS.isDirectory(path) else { continue }
            guard let mtime = CacheCleanerFS.modificationDate(path),
                  now().timeIntervalSince(mtime) >= staleAgeThreshold else { continue }

            items.append(ScanItem(
                path: path,
                sizeBytes: CacheCleanerFS.fileSize(path),
                sourceDetectorID: id,
                category: "Incomplete download",
                lastUsed: LastUsedEvidence(date: mtime, source: .filesystemMTime),
                reason: "'\(entry)' has a '\(suffix)' extension (used by browsers for in-progress downloads) but hasn't changed in \(daysText(staleAgeThreshold)) — looks abandoned rather than still downloading."
            ))
        }
        return items
    }
}
