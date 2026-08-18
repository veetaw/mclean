import Foundation
import CoreScanEngine

/// Finds Java/JVM toolchain caches and unused SDKMAN-managed installs:
/// - Gradle's dependency/build cache (`~/.gradle/caches`)
/// - Maven's local repository (`~/.m2/repository`)
/// - SDKMAN candidates that aren't the "current" version for their tool and
///   haven't been touched in a while
///
/// Strictly read-only. See `CoreScanEngine.Detector`.
public struct JavaDetector: Detector {
    public let id = "dev.java"
    public let displayName = "Java / JVM"
    public let category: DetectorCategory = .devTools

    private let staleCandidateThreshold: TimeInterval
    private let now: @Sendable () -> Date

    public init(
        staleCandidateThreshold: TimeInterval = 180 * 24 * 3600,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.staleCandidateThreshold = staleCandidateThreshold
        self.now = now
    }

    public func scan(context: ScanContext) async throws -> [ScanItem] {
        var items: [ScanItem] = []
        for home in HomeDirectories.resolve(context) {
            if Task.isCancelled { break }

            let gradle = home + "/.gradle/caches"
            if DevToolsFS.isDirectory(gradle) {
                items.append(ScanItem(
                    path: gradle,
                    sizeBytes: DevToolsFS.recursiveSize(of: gradle, isCancelled: { Task.isCancelled }),
                    sourceDetectorID: "dev.java.gradle-cache",
                    category: "Java — Gradle cache",
                    lastUsed: DevToolsFS.modificationDate(gradle).map { LastUsedEvidence(date: $0, source: .filesystemMTime) },
                    reason: "Gradle's downloaded-dependency and build-output cache. Re-populated automatically on the next build; safe to clear."
                ))
            }

            let maven = home + "/.m2/repository"
            if DevToolsFS.isDirectory(maven) {
                items.append(ScanItem(
                    path: maven,
                    sizeBytes: DevToolsFS.recursiveSize(of: maven, isCancelled: { Task.isCancelled }),
                    sourceDetectorID: "dev.java.maven-cache",
                    category: "Java — Maven local repository",
                    lastUsed: DevToolsFS.modificationDate(maven).map { LastUsedEvidence(date: $0, source: .filesystemMTime) },
                    reason: "Maven's local repository of downloaded artifacts. `mvn` re-downloads dependencies as needed; safe to clear."
                ))
            }

            items.append(contentsOf: scanSdkmanCandidates(home: home))
        }
        return items
    }

    private func scanSdkmanCandidates(home: String) -> [ScanItem] {
        let candidatesRoot = home + "/.sdkman/candidates"
        guard DevToolsFS.isDirectory(candidatesRoot) else { return [] }

        var items: [ScanItem] = []
        for candidate in DevToolsFS.directoryEntries(candidatesRoot) {
            let candidateDir = candidatesRoot + "/" + candidate
            guard DevToolsFS.isDirectory(candidateDir) else { continue }

            let currentLink = candidateDir + "/current"
            let currentTarget = try? FileManager.default.destinationOfSymbolicLink(atPath: currentLink)
                .split(separator: "/").last.map(String.init)

            for version in DevToolsFS.directoryEntries(candidateDir) {
                if version == "current" { continue }
                if let currentTarget, version == currentTarget { continue }
                let versionPath = candidateDir + "/" + version
                guard DevToolsFS.isDirectory(versionPath) else { continue }
                guard let mtime = DevToolsFS.modificationDate(versionPath),
                      now().timeIntervalSince(mtime) >= staleCandidateThreshold else { continue }

                items.append(ScanItem(
                    path: versionPath,
                    sizeBytes: DevToolsFS.recursiveSize(of: versionPath, isCancelled: { Task.isCancelled }),
                    sourceDetectorID: "dev.java.sdkman-unused-candidate",
                    category: "Java — unused SDKMAN candidate",
                    lastUsed: LastUsedEvidence(date: mtime, source: .filesystemMTime),
                    reason: "SDKMAN-managed \(candidate) \(version) is not the 'current' version for this candidate and hasn't been touched in \(daysText(staleCandidateThreshold)). Reinstallable via `sdk install \(candidate) \(version)` if needed again."
                ))
            }
        }
        return items
    }
}
