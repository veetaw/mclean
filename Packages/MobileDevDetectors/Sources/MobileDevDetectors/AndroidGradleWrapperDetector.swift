import Foundation
import CoreScanEngine

/// Flags superseded Gradle *wrapper* distributions under
/// `~/.gradle/wrapper/dists` — the per-version binaries that Android
/// Studio/Gradle wrapper downloads the first time a project requests a
/// given Gradle version.
///
/// This is intentionally narrow and distinct from the general `~/.gradle/caches`
/// dependency cache, which is `DevToolsDetectors`' responsibility (build-tool
/// caches in general, not Android-specific) — not duplicated here.
///
/// Each `dists/gradle-X.Y[.Z]-{bin,all}` directory typically holds one
/// hash-named subdirectory with the extracted distribution. As with the SDK
/// version detector, only versions strictly older than the newest installed
/// one are flagged, since an active project may still pin an older version.
public struct AndroidGradleWrapperDetector: Detector {
    public let id = "mobile.android.gradle-wrapper-stale"
    public let displayName = "Android — superseded Gradle wrapper distributions"
    public let category: DetectorCategory = .mobileDev

    private let wrapperDistsPath: String

    /// - Parameter wrapperDistsPath: Defaults to `~/.gradle/wrapper/dists`;
    ///   overridable for tests.
    public init(wrapperDistsPath: String = FSUtil.homeDirectory() + "/.gradle/wrapper/dists") {
        self.wrapperDistsPath = wrapperDistsPath
    }

    public func scan(context: ScanContext) async throws -> [ScanItem] {
        guard FSUtil.exists(atPath: wrapperDistsPath, isDirectory: true) else { return [] }

        let root = URL(fileURLWithPath: wrapperDistsPath)
        let entries = FSUtil.subdirectories(of: root)
        guard entries.count > 1 else { return [] }

        let parsed: [(url: URL, version: [Int])] = entries.compactMap { url in
            guard let v = FSUtil.versionComponents(from: url.lastPathComponent, strippingPrefixes: ["gradle-"]) else {
                return nil
            }
            return (url, v)
        }
        guard let newest = parsed.max(by: { versionArrayLess($0.version, $1.version) }) else { return [] }

        let superseded = parsed.filter { versionArrayLess($0.version, newest.version) }
        guard !superseded.isEmpty else { return [] }

        try Task.checkCancellation()
        let sizes = await FSUtil.sizes(of: superseded.map(\.url), maxConcurrency: context.maxConcurrency)

        return superseded.map { entry in
            let mtime = FSUtil.modificationDate(ofItemAt: entry.url.path)
            return ScanItem(
                path: entry.url.path,
                sizeBytes: sizes[entry.url],
                sourceDetectorID: id,
                category: "Android — Gradle wrapper distribution",
                lastUsed: mtime.map { LastUsedEvidence(date: $0, source: .filesystemMTime) },
                reason: """
                \(entry.url.lastPathComponent) is superseded by \(newest.url.lastPathComponent). \
                Gradle wrapper re-downloads a distribution automatically the next time a \
                project's gradle-wrapper.properties requests it, so this is only worth \
                removing once no active project still pins this version.
                """
            )
        }
    }
}
