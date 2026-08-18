import Foundation
import CoreScanEngine

/// Finds Node.js/JavaScript toolchain caches and stale artifacts:
/// - `node_modules` directories not modified in a configurable threshold
///   (default 90 days)
/// - npm / Yarn / pnpm package manager caches
/// - build-tool caches (Turborepo's `.turbo`, `node_modules/.cache` used by
///   webpack/vite/babel and friends)
///
/// Strictly read-only. See `CoreScanEngine.Detector`.
public struct NodeDetector: Detector {
    public let id = "dev.node"
    public let displayName = "Node.js / JavaScript"
    public let category: DetectorCategory = .devTools

    private let staleNodeModulesThreshold: TimeInterval
    private let now: @Sendable () -> Date

    public init(
        staleNodeModulesThreshold: TimeInterval = 90 * 24 * 3600,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.staleNodeModulesThreshold = staleNodeModulesThreshold
        self.now = now
    }

    public func scan(context: ScanContext) async throws -> [ScanItem] {
        var items: [ScanItem] = []
        for home in HomeDirectories.resolve(context) {
            if Task.isCancelled { break }
            items.append(contentsOf: scanPackageManagerCaches(home: home))
            items.append(contentsOf: scanStaleNodeModules(home: home))
            if Task.isCancelled { break }
            items.append(contentsOf: scanBuildToolCaches(home: home))
        }
        return items
    }

    // MARK: - package manager caches

    private func scanPackageManagerCaches(home: String) -> [ScanItem] {
        struct Candidate { let path: String; let id: String; let label: String; let reason: String }

        let candidates: [Candidate] = [
            Candidate(
                path: home + "/.npm",
                id: "dev.node.npm-cache",
                label: "Node — npm cache",
                reason: "npm's package download cache. npm re-downloads tarballs as needed on the next install; safe to clear (or run `npm cache clean --force`)."
            ),
            Candidate(
                path: home + "/Library/Caches/Yarn",
                id: "dev.node.yarn-cache",
                label: "Node — Yarn cache",
                reason: "Yarn's package cache. Yarn re-downloads packages as needed on the next install; safe to clear."
            ),
            Candidate(
                path: home + "/.cache/yarn",
                id: "dev.node.yarn-cache",
                label: "Node — Yarn cache",
                reason: "Yarn's package cache. Yarn re-downloads packages as needed on the next install; safe to clear."
            ),
            Candidate(
                path: home + "/Library/pnpm/store",
                id: "dev.node.pnpm-store",
                label: "Node — pnpm store",
                reason: "pnpm's content-addressable package store, shared (via hard links) across every pnpm project on this machine. Clearing it forces pnpm to re-fetch and re-link packages on the next install."
            ),
            Candidate(
                path: home + "/.local/share/pnpm/store",
                id: "dev.node.pnpm-store",
                label: "Node — pnpm store",
                reason: "pnpm's content-addressable package store, shared (via hard links) across every pnpm project on this machine. Clearing it forces pnpm to re-fetch and re-link packages on the next install."
            )
        ]

        var items: [ScanItem] = []
        for candidate in candidates {
            guard DevToolsFS.isDirectory(candidate.path) else { continue }
            items.append(ScanItem(
                path: candidate.path,
                sizeBytes: DevToolsFS.recursiveSize(of: candidate.path, isCancelled: { Task.isCancelled }),
                sourceDetectorID: candidate.id,
                category: candidate.label,
                lastUsed: DevToolsFS.modificationDate(candidate.path).map { LastUsedEvidence(date: $0, source: .filesystemMTime) },
                reason: candidate.reason
            ))
        }
        return items
    }

    // MARK: - stale node_modules

    private func scanStaleNodeModules(home: String) -> [ScanItem] {
        let matches = DevToolsFS.findDirectories(
            under: home,
            maxDepth: 8,
            skipping: [".git", "Library", ".Trash"],
            isCancelled: { Task.isCancelled }
        ) { name, _ in name == "node_modules" }

        var items: [ScanItem] = []
        for path in matches {
            let projectDir = String(path.dropLast("/node_modules".count))
            let evidence = lastUsedEvidence(forProjectAt: projectDir, fallbackPath: path)
            guard let date = evidence?.date, now().timeIntervalSince(date) >= staleNodeModulesThreshold else { continue }

            var reason = "node_modules not modified in \(daysText(staleNodeModulesThreshold)) (evidence: \(evidence?.source.rawValue ?? "unknown")). The package manager reinstalls it from the lockfile/manifest as needed."
            if DevToolsFS.isDirectory(projectDir + "/.git") {
                reason += " Parent project (\(projectDir)) has an active git repository — this detector does not check `git status`; verify no uncommitted work depends on these dependencies before removing (that check belongs to SafetyRules, not this detector)."
            }

            items.append(ScanItem(
                path: path,
                sizeBytes: DevToolsFS.recursiveSize(of: path, isCancelled: { Task.isCancelled }),
                sourceDetectorID: "dev.node.stale-node-modules",
                category: "Node — stale node_modules",
                lastUsed: evidence,
                reason: reason
            ))
        }
        return items
    }

    private func lastUsedEvidence(forProjectAt projectDir: String, fallbackPath: String) -> LastUsedEvidence? {
        for lockfile in ["package-lock.json", "yarn.lock", "pnpm-lock.yaml"] {
            let lockPath = projectDir + "/" + lockfile
            if let date = DevToolsFS.modificationDate(lockPath) {
                return LastUsedEvidence(date: date, source: .manifestOrLockfileMTime)
            }
        }
        if let date = DevToolsFS.modificationDate(fallbackPath) {
            return LastUsedEvidence(date: date, source: .filesystemMTime)
        }
        return nil
    }

    // MARK: - build tool caches

    private func scanBuildToolCaches(home: String) -> [ScanItem] {
        var items: [ScanItem] = []

        let turboDirs = DevToolsFS.findDirectories(
            under: home,
            maxDepth: 8,
            skipping: [".git", "Library", ".Trash", "node_modules"],
            isCancelled: { Task.isCancelled }
        ) { name, _ in name == ".turbo" }

        for path in turboDirs {
            items.append(ScanItem(
                path: path,
                sizeBytes: DevToolsFS.recursiveSize(of: path, isCancelled: { Task.isCancelled }),
                sourceDetectorID: "dev.node.turborepo-cache",
                category: "Node — Turborepo cache",
                lastUsed: DevToolsFS.modificationDate(path).map { LastUsedEvidence(date: $0, source: .filesystemMTime) },
                reason: "Turborepo's local task-output cache (.turbo). Turborepo re-runs and re-caches tasks as needed; safe to clear."
            ))
        }

        let nodeModulesDirs = DevToolsFS.findDirectories(
            under: home,
            maxDepth: 8,
            skipping: [".git", "Library", ".Trash"],
            isCancelled: { Task.isCancelled }
        ) { name, _ in name == "node_modules" }

        for nodeModules in nodeModulesDirs {
            let cachePath = nodeModules + "/.cache"
            guard DevToolsFS.isDirectory(cachePath) else { continue }
            items.append(ScanItem(
                path: cachePath,
                sizeBytes: DevToolsFS.recursiveSize(of: cachePath, isCancelled: { Task.isCancelled }),
                sourceDetectorID: "dev.node.bundler-cache",
                category: "Node — bundler cache (webpack/vite/babel)",
                lastUsed: DevToolsFS.modificationDate(cachePath).map { LastUsedEvidence(date: $0, source: .filesystemMTime) },
                reason: "Build-tool cache written inside node_modules/.cache (webpack, vite, babel-loader, and similar). Regenerated automatically on the next build; safe to clear even if node_modules itself stays."
            ))
        }

        return items
    }
}
