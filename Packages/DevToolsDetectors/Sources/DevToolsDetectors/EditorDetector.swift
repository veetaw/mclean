import Foundation
import CoreScanEngine

/// Finds editor/IDE caches and best-effort-unused extensions:
/// - JetBrains per-installation caches (`~/Library/Caches/JetBrains/...`)
/// - VS Code's own cache directories (`~/Library/Application Support/Code/Cache*`)
/// - VS Code extensions that look old/unused (best-effort by mtime — VS Code
///   doesn't record a real per-extension last-used date on disk)
///
/// Strictly read-only. See `CoreScanEngine.Detector`.
public struct EditorDetector: Detector {
    public let id = "dev.editors"
    public let displayName = "Editors & IDEs"
    public let category: DetectorCategory = .devTools

    private let staleExtensionThreshold: TimeInterval
    private let now: @Sendable () -> Date

    public init(
        staleExtensionThreshold: TimeInterval = 180 * 24 * 3600,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.staleExtensionThreshold = staleExtensionThreshold
        self.now = now
    }

    public func scan(context: ScanContext) async throws -> [ScanItem] {
        var items: [ScanItem] = []
        for home in HomeDirectories.resolve(context) {
            if Task.isCancelled { break }
            items.append(contentsOf: scanJetBrainsCaches(home: home))
            items.append(contentsOf: scanVSCodeCaches(home: home))
            items.append(contentsOf: scanVSCodeExtensions(home: home))
        }
        return items
    }

    private func scanJetBrainsCaches(home: String) -> [ScanItem] {
        let root = home + "/Library/Caches/JetBrains"
        guard DevToolsFS.isDirectory(root) else { return [] }

        return DevToolsFS.directoryEntries(root).compactMap { entry in
            let path = root + "/" + entry
            guard DevToolsFS.isDirectory(path) else { return nil }
            return ScanItem(
                path: path,
                sizeBytes: DevToolsFS.recursiveSize(of: path, isCancelled: { Task.isCancelled }),
                sourceDetectorID: "dev.editors.jetbrains-cache",
                category: "Editors — JetBrains cache",
                lastUsed: DevToolsFS.modificationDate(path).map { LastUsedEvidence(date: $0, source: .filesystemMTime) },
                reason: "Per-installation cache for '\(entry)' (indexes, compile-server output, previews). JetBrains IDEs rebuild these automatically, even for the currently installed version; safe to clear."
            )
        }
    }

    private func scanVSCodeCaches(home: String) -> [ScanItem] {
        let root = home + "/Library/Application Support/Code"
        guard DevToolsFS.isDirectory(root) else { return [] }

        return DevToolsFS.directoryEntries(root)
            .filter { $0.hasPrefix("Cache") || $0 == "CachedData" || $0 == "GPUCache" }
            .compactMap { entry in
                let path = root + "/" + entry
                guard DevToolsFS.isDirectory(path) else { return nil }
                return ScanItem(
                    path: path,
                    sizeBytes: DevToolsFS.recursiveSize(of: path, isCancelled: { Task.isCancelled }),
                    sourceDetectorID: "dev.editors.vscode-cache",
                    category: "Editors — VS Code cache",
                    lastUsed: DevToolsFS.modificationDate(path).map { LastUsedEvidence(date: $0, source: .filesystemMTime) },
                    reason: "VS Code internal cache directory '\(entry)'. Regenerated automatically on next launch; safe to clear."
                )
            }
    }

    private func scanVSCodeExtensions(home: String) -> [ScanItem] {
        let root = home + "/.vscode/extensions"
        guard DevToolsFS.isDirectory(root) else { return [] }

        var items: [ScanItem] = []
        for entry in DevToolsFS.directoryEntries(root) {
            guard !entry.hasPrefix(".") else { continue }
            let path = root + "/" + entry
            guard DevToolsFS.isDirectory(path) else { continue }
            guard let mtime = DevToolsFS.modificationDate(path),
                  now().timeIntervalSince(mtime) >= staleExtensionThreshold else { continue }

            items.append(ScanItem(
                path: path,
                sizeBytes: DevToolsFS.recursiveSize(of: path, isCancelled: { Task.isCancelled }),
                sourceDetectorID: "dev.editors.vscode-unused-extension",
                category: "Editors — possibly unused VS Code extension",
                lastUsed: LastUsedEvidence(date: mtime, source: .filesystemMTime),
                reason: "Extension '\(entry)' folder untouched for \(daysText(staleExtensionThreshold)). Best-effort mtime heuristic, not real usage tracking (VS Code doesn't record a per-extension last-used date on disk) — verify it's actually unused before removing; reinstallable from the Marketplace."
            ))
        }
        return items
    }
}
