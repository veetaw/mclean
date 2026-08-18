import Foundation
import CoreScanEngine

/// Finds Go toolchain caches:
/// - the module cache (`$GOPATH/pkg/mod`, defaulting to `~/go/pkg/mod`)
/// - the build cache (`$GOCACHE`, defaulting to `~/Library/Caches/go-build`)
///
/// Strictly read-only. See `CoreScanEngine.Detector`.
public struct GoDetector: Detector {
    public let id = "dev.go"
    public let displayName = "Go"
    public let category: DetectorCategory = .devTools

    /// Injectable so tests can simulate `GOPATH`/`GOCACHE` without relying on
    /// the real environment (or Go actually being installed).
    private let environment: [String: String]

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.environment = environment
    }

    public func scan(context: ScanContext) async throws -> [ScanItem] {
        var items: [ScanItem] = []
        for home in HomeDirectories.resolve(context) {
            if Task.isCancelled { break }

            let modCache = environment["GOPATH"].map { $0 + "/pkg/mod" } ?? (home + "/go/pkg/mod")
            if DevToolsFS.isDirectory(modCache) {
                items.append(ScanItem(
                    path: modCache,
                    sizeBytes: DevToolsFS.recursiveSize(of: modCache, isCancelled: { Task.isCancelled }),
                    sourceDetectorID: "dev.go.module-cache",
                    category: "Go — module cache",
                    lastUsed: DevToolsFS.modificationDate(modCache).map { LastUsedEvidence(date: $0, source: .filesystemMTime) },
                    reason: "Downloaded Go module sources (GOPATH/pkg/mod). `go build`/`go mod download` re-fetch modules as needed; clear via `go clean -modcache` rather than deleting by hand where possible."
                ))
            }

            let buildCache = environment["GOCACHE"] ?? (home + "/Library/Caches/go-build")
            if DevToolsFS.isDirectory(buildCache) {
                items.append(ScanItem(
                    path: buildCache,
                    sizeBytes: DevToolsFS.recursiveSize(of: buildCache, isCancelled: { Task.isCancelled }),
                    sourceDetectorID: "dev.go.build-cache",
                    category: "Go — build cache",
                    lastUsed: DevToolsFS.modificationDate(buildCache).map { LastUsedEvidence(date: $0, source: .filesystemMTime) },
                    reason: "Go's compiler build cache. Regenerated automatically; clearing it only costs a slower next build (`go clean -cache`)."
                ))
            }
        }
        return items
    }
}
