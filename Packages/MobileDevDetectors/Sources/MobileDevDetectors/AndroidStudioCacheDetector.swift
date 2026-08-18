import Foundation
import CoreScanEngine

/// Flags Android Studio's regenerable cache directories:
/// - `~/Library/Caches/Google/AndroidStudio*` (the whole directory — it is
///   already under `~/Library/Caches`, so entirely regenerable by design).
/// - `~/Library/Application Support/Google/AndroidStudio*/caches` (only the
///   `caches` subdirectory — the rest of `Application Support/.../AndroidStudio*`
///   holds real settings/config and must not be touched by this detector).
///
/// Matches any number of installed Android Studio versions (e.g.
/// `AndroidStudio2023.1`, `AndroidStudioGiraffe`) via a simple name-prefix
/// scan — no globbing dependency required.
public struct AndroidStudioCacheDetector: Detector {
    public let id = "mobile.android.studio-caches"
    public let displayName = "Android Studio — IDE caches"
    public let category: DetectorCategory = .mobileDev

    private let cachesRootPath: String
    private let applicationSupportRootPath: String

    /// - Parameters:
    ///   - cachesRootPath: Defaults to `~/Library/Caches/Google`.
    ///   - applicationSupportRootPath: Defaults to
    ///     `~/Library/Application Support/Google`.
    public init(
        cachesRootPath: String = FSUtil.homeDirectory() + "/Library/Caches/Google",
        applicationSupportRootPath: String = FSUtil.homeDirectory() + "/Library/Application Support/Google"
    ) {
        self.cachesRootPath = cachesRootPath
        self.applicationSupportRootPath = applicationSupportRootPath
    }

    public func scan(context: ScanContext) async throws -> [ScanItem] {
        var candidates: [(url: URL, reason: String)] = []

        if FSUtil.exists(atPath: cachesRootPath, isDirectory: true) {
            let matches = FSUtil.entries(in: URL(fileURLWithPath: cachesRootPath), namePrefix: "AndroidStudio")
            candidates += matches.map { url in
                (url, "Android Studio cache directory (\(url.lastPathComponent)); regenerated automatically on next launch.")
            }
        }

        try Task.checkCancellation()

        if FSUtil.exists(atPath: applicationSupportRootPath, isDirectory: true) {
            let appSupportMatches = FSUtil.entries(
                in: URL(fileURLWithPath: applicationSupportRootPath),
                namePrefix: "AndroidStudio"
            )
            for appSupportDir in appSupportMatches {
                let cachesSubdir = appSupportDir.appendingPathComponent("caches")
                guard FSUtil.exists(atPath: cachesSubdir.path, isDirectory: true) else { continue }
                candidates.append((
                    cachesSubdir,
                    "Android Studio build/index cache under Application Support (\(appSupportDir.lastPathComponent)/caches); settings in the parent directory are left untouched."
                ))
            }
        }

        guard !candidates.isEmpty else { return [] }

        try Task.checkCancellation()
        let sizes = await FSUtil.sizes(of: candidates.map(\.url), maxConcurrency: context.maxConcurrency)

        return candidates.map { entry in
            let mtime = FSUtil.modificationDate(ofItemAt: entry.url.path)
            return ScanItem(
                path: entry.url.path,
                sizeBytes: sizes[entry.url],
                sourceDetectorID: id,
                category: "Android Studio — IDE cache",
                lastUsed: mtime.map { LastUsedEvidence(date: $0, source: .filesystemMTime) },
                reason: entry.reason
            )
        }
    }
}
