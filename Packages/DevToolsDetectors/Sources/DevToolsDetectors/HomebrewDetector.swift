import Foundation
import CoreScanEngine

/// Finds Homebrew's own download cache (`~/Library/Caches/Homebrew`) as
/// regular, per-item `ScanItem`s — that part is a plain filesystem
/// directory, safe to enumerate and quarantine like any other cache.
///
/// Homebrew's other maintenance operations, `brew cleanup` and
/// `brew autoremove`, are deliberately **not** modeled as scan results:
/// they mutate Homebrew's own bookkeeping of installed formulae/casks
/// (uninstalling old versions, removing now-unneeded dependencies) rather
/// than pointing at a single path this app could move to quarantine. Running
/// them is left to the user; see `HomebrewDetector.guidedActions` for the
/// descriptive (non-executing) suggestions surfaced to the UI instead.
///
/// Strictly read-only. See `CoreScanEngine.Detector`.
public struct HomebrewDetector: Detector {
    public let id = "dev.homebrew"
    public let displayName = "Homebrew"
    public let category: DetectorCategory = .devTools

    public init() {}

    public func scan(context: ScanContext) async throws -> [ScanItem] {
        var items: [ScanItem] = []
        for home in HomeDirectories.resolve(context) {
            if Task.isCancelled { break }
            let cacheRoot = home + "/Library/Caches/Homebrew"
            guard DevToolsFS.isDirectory(cacheRoot) else { continue }

            for entry in DevToolsFS.directoryEntries(cacheRoot) {
                let path = cacheRoot + "/" + entry
                items.append(ScanItem(
                    path: path,
                    sizeBytes: DevToolsFS.recursiveSize(of: path, isCancelled: { Task.isCancelled }),
                    sourceDetectorID: "dev.homebrew.download-cache",
                    category: "Homebrew — download cache",
                    lastUsed: DevToolsFS.modificationDate(path).map { LastUsedEvidence(date: $0, source: .filesystemMTime) },
                    reason: "Homebrew's downloaded formula/cask archive '\(entry)'. Homebrew re-downloads as needed; this is exactly what `brew cleanup` also removes."
                ))
            }
        }
        return items
    }

    /// Suggested Homebrew maintenance commands, surfaced to the UI as
    /// guided actions rather than executed by this detector. See the type
    /// doc comment above for why these aren't `ScanItem`s.
    public static let guidedActions: [DevToolsGuidedAction] = [
        DevToolsGuidedAction(
            id: "dev.homebrew.action.cleanup",
            title: "Run brew cleanup",
            command: "brew cleanup",
            explanation: "Removes old/outdated versions of installed formulae and casks, plus Homebrew's own download cache. MClean Pro only suggests this command — it is never run automatically."
        ),
        DevToolsGuidedAction(
            id: "dev.homebrew.action.autoremove",
            title: "Run brew autoremove",
            command: "brew autoremove",
            explanation: "Uninstalls formulae that were only ever installed as another formula's dependency and are no longer required by anything. MClean Pro only suggests this command — it is never run automatically."
        )
    ]
}
