import Foundation
import CoreScanEngine

/// Flags Fastlane's global cache directory and, best-effort, per-project
/// `fastlane/report.xml` / `fastlane/test_output` artifacts.
///
/// This is deliberately *not* a full project scanner: it does a
/// bounded-depth walk (default 4 levels) under `context.roots` (or, if none
/// are supplied, a short list of common project parent directories), and
/// explicitly skips heavy/vendored directory names it has no business
/// descending into (`node_modules`, `Pods`, `DerivedData`, `.git`, ...).
public struct FastlaneCacheDetector: Detector {
    public let id = "mobile.ios.fastlane-cache"
    public let displayName = "Fastlane — cache and run output"
    public let category: DetectorCategory = .mobileDev

    private static let skippedDirectoryNames: Set<String> = [
        "node_modules", "Pods", "DerivedData", ".build", "Carthage",
        "build", "vendor", "fastlane" // avoid descending into an already-found fastlane dir
    ]

    private let globalCachePath: String
    private let projectSearchRoots: [String]
    private let maxSearchDepth: Int

    /// - Parameters:
    ///   - globalCachePath: Defaults to `~/Library/Caches/fastlane`.
    ///   - projectSearchRoots: Directories to search for per-project
    ///     `fastlane/` directories. When `nil`, falls back to
    ///     `~/Developer`, `~/Projects`, `~/Documents` if `context.roots` is
    ///     also empty at scan time.
    ///   - maxSearchDepth: Maximum directory levels to descend while
    ///     looking for `fastlane/` directories.
    public init(
        globalCachePath: String = FSUtil.homeDirectory() + "/Library/Caches/fastlane",
        projectSearchRoots: [String]? = nil,
        maxSearchDepth: Int = 4
    ) {
        self.globalCachePath = globalCachePath
        if let projectSearchRoots {
            self.projectSearchRoots = projectSearchRoots
        } else {
            let home = FSUtil.homeDirectory()
            self.projectSearchRoots = ["\(home)/Developer", "\(home)/Projects", "\(home)/Documents"]
        }
        self.maxSearchDepth = maxSearchDepth
    }

    public func scan(context: ScanContext) async throws -> [ScanItem] {
        var items: [ScanItem] = []

        if FSUtil.exists(atPath: globalCachePath, isDirectory: true) {
            let url = URL(fileURLWithPath: globalCachePath)
            let size = await FSUtil.directorySize(at: url)
            let mtime = FSUtil.modificationDate(ofItemAt: globalCachePath)
            items.append(ScanItem(
                path: globalCachePath,
                sizeBytes: size,
                sourceDetectorID: id,
                category: "Fastlane — global cache",
                lastUsed: mtime.map { LastUsedEvidence(date: $0, source: .filesystemMTime) },
                reason: "Fastlane's global cache directory; safe to clear, Fastlane repopulates it as needed."
            ))
        }

        try Task.checkCancellation()

        let searchRoots = context.roots.isEmpty ? projectSearchRoots : context.roots
        var fastlaneDirs: [URL] = []
        for rootPath in searchRoots {
            try Task.checkCancellation()
            guard FSUtil.exists(atPath: rootPath, isDirectory: true) else { continue }
            fastlaneDirs += Self.findFastlaneDirectories(under: URL(fileURLWithPath: rootPath), remainingDepth: maxSearchDepth)
        }

        for fastlaneDir in fastlaneDirs {
            try Task.checkCancellation()
            let projectName = fastlaneDir.deletingLastPathComponent().lastPathComponent

            let reportURL = fastlaneDir.appendingPathComponent("report.xml")
            if FSUtil.exists(atPath: reportURL.path, isDirectory: false) {
                let size = await FSUtil.directorySize(at: reportURL)
                let mtime = FSUtil.modificationDate(ofItemAt: reportURL.path)
                items.append(ScanItem(
                    path: reportURL.path,
                    sizeBytes: size,
                    sourceDetectorID: id,
                    category: "Fastlane — report output",
                    lastUsed: mtime.map { LastUsedEvidence(date: $0, source: .filesystemMTime) },
                    reason: "Fastlane run report for project \"\(projectName)\"; regenerated on the next `fastlane` invocation."
                ))
            }

            let testOutputURL = fastlaneDir.appendingPathComponent("test_output")
            if FSUtil.exists(atPath: testOutputURL.path, isDirectory: true) {
                let size = await FSUtil.directorySize(at: testOutputURL)
                let mtime = FSUtil.modificationDate(ofItemAt: testOutputURL.path)
                items.append(ScanItem(
                    path: testOutputURL.path,
                    sizeBytes: size,
                    sourceDetectorID: id,
                    category: "Fastlane — test output",
                    lastUsed: mtime.map { LastUsedEvidence(date: $0, source: .filesystemMTime) },
                    reason: "Fastlane test_output for project \"\(projectName)\"; regenerated on the next test run."
                ))
            }
        }

        return items
    }

    /// Bounded-depth, synchronous directory walk looking for directories
    /// literally named `fastlane`. Not a general project scanner: stops at
    /// `remainingDepth` levels and skips common heavy/vendored directories.
    private static func findFastlaneDirectories(under url: URL, remainingDepth: Int) -> [URL] {
        guard remainingDepth > 0, !Task.isCancelled else { return [] }
        var results: [URL] = []
        for child in FSUtil.subdirectories(of: url) {
            if Task.isCancelled { break }
            let name = child.lastPathComponent
            if name == "fastlane" {
                results.append(child)
                continue
            }
            guard !skippedDirectoryNames.contains(name) else { continue }
            results += findFastlaneDirectories(under: child, remainingDepth: remainingDepth - 1)
        }
        return results
    }
}
