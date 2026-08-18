import Foundation
import CoreScanEngine

/// Flags CocoaPods' cache locations:
/// - `~/Library/Caches/CocoaPods` — downloaded pod sources/specs, entirely
///   regenerable via `pod install`.
/// - `~/.cocoapods` — the CocoaPods home directory, which mainly holds spec
///   repos (re-clonable via `pod repo update`) but can also hold trunk
///   credentials; flagged with an explicit note rather than silently.
///
/// Both are reported unconditionally when present (no staleness threshold):
/// unlike a build tool's dependency cache, these are pure caches by design
/// and worth surfacing in the "reclaimable space" total regardless of age.
public struct CocoaPodsCacheDetector: Detector {
    public let id = "mobile.ios.cocoapods-cache"
    public let displayName = "CocoaPods — cache"
    public let category: DetectorCategory = .mobileDev

    private let cachesPath: String
    private let dotCocoaPodsPath: String

    /// - Parameters:
    ///   - cachesPath: Defaults to `~/Library/Caches/CocoaPods`.
    ///   - dotCocoaPodsPath: Defaults to `~/.cocoapods`.
    public init(
        cachesPath: String = FSUtil.homeDirectory() + "/Library/Caches/CocoaPods",
        dotCocoaPodsPath: String = FSUtil.homeDirectory() + "/.cocoapods"
    ) {
        self.cachesPath = cachesPath
        self.dotCocoaPodsPath = dotCocoaPodsPath
    }

    public func scan(context: ScanContext) async throws -> [ScanItem] {
        var candidates: [(path: String, category: String, reason: String)] = []

        if FSUtil.exists(atPath: cachesPath, isDirectory: true) {
            candidates.append((
                cachesPath,
                "CocoaPods — pod cache",
                "Downloaded pod sources/specs cache; regenerated automatically on the next `pod install`."
            ))
        }
        if FSUtil.exists(atPath: dotCocoaPodsPath, isDirectory: true) {
            candidates.append((
                dotCocoaPodsPath,
                "CocoaPods — home directory",
                "CocoaPods home directory (mainly spec repos, re-clonable via `pod repo update`/`pod install`). " +
                "May also contain trunk credentials — review before removing rather than clearing blindly."
            ))
        }
        guard !candidates.isEmpty else { return [] }

        try Task.checkCancellation()
        let urls = candidates.map { URL(fileURLWithPath: $0.path) }
        let sizes = await FSUtil.sizes(of: urls, maxConcurrency: context.maxConcurrency)

        return candidates.map { entry in
            let url = URL(fileURLWithPath: entry.path)
            let mtime = FSUtil.modificationDate(ofItemAt: entry.path)
            return ScanItem(
                path: entry.path,
                sizeBytes: sizes[url],
                sourceDetectorID: id,
                category: entry.category,
                lastUsed: mtime.map { LastUsedEvidence(date: $0, source: .filesystemMTime) },
                reason: entry.reason
            )
        }
    }
}
