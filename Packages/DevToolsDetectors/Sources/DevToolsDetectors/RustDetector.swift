import Foundation
import CoreScanEngine

/// Finds Rust/Cargo toolchain caches and stale build artifacts:
/// - Cargo's registry cache (`~/.cargo/registry`: downloaded crate archives,
///   extracted sources, index metadata)
/// - per-project `target/` directories with an old mtime
///
/// Strictly read-only. See `CoreScanEngine.Detector`.
public struct RustDetector: Detector {
    public let id = "dev.rust"
    public let displayName = "Rust"
    public let category: DetectorCategory = .devTools

    private let staleTargetThreshold: TimeInterval
    private let now: @Sendable () -> Date

    public init(
        staleTargetThreshold: TimeInterval = 30 * 24 * 3600,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.staleTargetThreshold = staleTargetThreshold
        self.now = now
    }

    public func scan(context: ScanContext) async throws -> [ScanItem] {
        var items: [ScanItem] = []
        for home in HomeDirectories.resolve(context) {
            if Task.isCancelled { break }
            items.append(contentsOf: scanCargoRegistry(home: home))
            if Task.isCancelled { break }
            items.append(contentsOf: scanStaleTargetDirs(home: home))
        }
        return items
    }

    // MARK: - registry cache

    private func scanCargoRegistry(home: String) -> [ScanItem] {
        let base = home + "/.cargo/registry"
        guard DevToolsFS.isDirectory(base) else { return [] }

        let subpaths: [(name: String, id: String, reason: String)] = [
            ("cache", "dev.rust.cargo-registry-cache", "Downloaded crate archives (.crate files). cargo re-downloads them from the registry as needed."),
            ("src", "dev.rust.cargo-registry-src", "Extracted crate sources, unpacked from the .crate cache. Re-extracted automatically as needed."),
            ("index", "dev.rust.cargo-registry-index", "Registry index metadata (crate name/version listings). Re-fetched automatically on next build.")
        ]

        var items: [ScanItem] = []
        for (name, sourceID, reasonDetail) in subpaths {
            let path = base + "/" + name
            guard DevToolsFS.isDirectory(path) else { continue }
            items.append(ScanItem(
                path: path,
                sizeBytes: DevToolsFS.recursiveSize(of: path, isCancelled: { Task.isCancelled }),
                sourceDetectorID: sourceID,
                category: "Rust — Cargo registry",
                lastUsed: DevToolsFS.modificationDate(path).map { LastUsedEvidence(date: $0, source: .filesystemMTime) },
                reason: "\(reasonDetail) Safe to clear."
            ))
        }

        if items.isEmpty {
            items.append(ScanItem(
                path: base,
                sizeBytes: DevToolsFS.recursiveSize(of: base, isCancelled: { Task.isCancelled }),
                sourceDetectorID: "dev.rust.cargo-registry",
                category: "Rust — Cargo registry",
                lastUsed: DevToolsFS.modificationDate(base).map { LastUsedEvidence(date: $0, source: .filesystemMTime) },
                reason: "Cargo's registry cache (downloaded crates and index metadata). cargo re-downloads dependencies as needed; safe to clear."
            ))
        }
        return items
    }

    // MARK: - stale target/ dirs

    private func scanStaleTargetDirs(home: String) -> [ScanItem] {
        let matches = DevToolsFS.findDirectories(
            under: home,
            maxDepth: 8,
            skipping: [".git", "Library", ".Trash", "node_modules"],
            isCancelled: { Task.isCancelled }
        ) { name, path in
            guard name == "target" else { return false }
            let projectDir = String(path.dropLast("/target".count))
            return DevToolsFS.exists(projectDir + "/Cargo.toml")
        }

        var items: [ScanItem] = []
        for path in matches {
            let projectDir = String(path.dropLast("/target".count))
            let manifestPath = projectDir + "/Cargo.toml"

            let evidence: LastUsedEvidence?
            if let date = DevToolsFS.modificationDate(manifestPath) {
                evidence = LastUsedEvidence(date: date, source: .manifestOrLockfileMTime)
            } else {
                evidence = DevToolsFS.modificationDate(path).map { LastUsedEvidence(date: $0, source: .filesystemMTime) }
            }
            guard let date = evidence?.date, now().timeIntervalSince(date) >= staleTargetThreshold else { continue }

            items.append(ScanItem(
                path: path,
                sizeBytes: DevToolsFS.recursiveSize(of: path, isCancelled: { Task.isCancelled }),
                sourceDetectorID: "dev.rust.stale-target-dir",
                category: "Rust — stale target/ build directory",
                lastUsed: evidence,
                reason: "Cargo build output for the project at \(projectDir), untouched for \(daysText(staleTargetThreshold)) (evidence: \(evidence?.source.rawValue ?? "unknown")). `cargo build` regenerates it from source."
            ))
        }
        return items
    }
}
