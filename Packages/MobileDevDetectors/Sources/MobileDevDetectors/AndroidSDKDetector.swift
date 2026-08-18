import Foundation
import CoreScanEngine

/// Flags Android SDK `platforms/` and `build-tools/` versions that are
/// clearly superseded by a newer version installed alongside them (e.g.
/// `android-30` when `android-34` is also present).
///
/// Deliberately conservative: a version is only flagged when a *strictly
/// newer* one exists in the same directory. A single installed version is
/// never flagged — there's nothing to be "superseded by" yet, and it may
/// still be required by an active project's `compileSdkVersion`.
public struct AndroidSDKDetector: Detector {
    public let id = "mobile.android.sdk-obsolete-versions"
    public let displayName = "Android SDK — superseded platform / build-tools versions"
    public let category: DetectorCategory = .mobileDev

    private let sdkRootPath: String

    /// - Parameter sdkRootPath: Android SDK root. Defaults to
    ///   `~/Library/Android/sdk`; overridable for tests.
    public init(sdkRootPath: String = FSUtil.homeDirectory() + "/Library/Android/sdk") {
        self.sdkRootPath = sdkRootPath
    }

    public func scan(context: ScanContext) async throws -> [ScanItem] {
        var items: [ScanItem] = []
        items += try await scanVersionedDirectory(
            named: "platforms",
            categoryLabel: "Android SDK — platform",
            stripPrefixes: ["android-"],
            context: context
        )
        try Task.checkCancellation()
        items += try await scanVersionedDirectory(
            named: "build-tools",
            categoryLabel: "Android SDK — build-tools",
            stripPrefixes: [],
            context: context
        )
        return items
    }

    private func scanVersionedDirectory(
        named subdirectory: String,
        categoryLabel: String,
        stripPrefixes: [String],
        context: ScanContext
    ) async throws -> [ScanItem] {
        let dirPath = sdkRootPath + "/" + subdirectory
        guard FSUtil.exists(atPath: dirPath, isDirectory: true) else { return [] }

        let root = URL(fileURLWithPath: dirPath)
        let entries = FSUtil.subdirectories(of: root)
        guard entries.count > 1 else { return [] }

        let parsed: [(url: URL, version: [Int])] = entries.compactMap { url in
            guard let v = FSUtil.versionComponents(from: url.lastPathComponent, strippingPrefixes: stripPrefixes) else {
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
                category: categoryLabel,
                lastUsed: mtime.map { LastUsedEvidence(date: $0, source: .filesystemMTime) },
                reason: """
                \(entry.url.lastPathComponent) is superseded by \(newest.url.lastPathComponent), \
                the newest version installed under \(subdirectory). Kept only if a project still \
                targets this exact version — verify no active project pins it before removing.
                """
            )
        }
    }
}
