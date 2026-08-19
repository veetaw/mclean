import Foundation
import CoreScanEngine

/// Finds large and/or old files sitting in the user's common file-management
/// directories — PROMPT MASTER §5.1's "Large & Old Files finder con filtri
/// per dimensione/data/tipo."
///
/// Strictly read-only, like every `CoreScanEngine.Detector` in this repo:
/// this package only *finds* candidates. Every `ScanItem` it produces still
/// flows through `SafetyRules.SafetyClassifier` at the single chokepoint in
/// `MainAppUI` before anything is ever offered for quarantine (hardcoded
/// denylist, credential directories, `.env`/`.pem`/`.key` files, dirty-git
/// checks, system paths) — this detector does not duplicate any of that.
///
/// ## Scope
/// By default this finder does **not** walk the entire home directory. It
/// scopes itself to `LargeOldFilesFinderConfig.defaultScopedDirectories`
/// (Downloads/Desktop/Documents/Movies/Music/Pictures) so it doesn't
/// re-surface territory other detectors already own: `~/Library/Caches`,
/// `node_modules`, `.git` internals, and developer/mobile toolchain state
/// (DevToolsDetectors/MobileDevDetectors/PowerUserInspectors' territory) are
/// all explicitly excluded — see `LargeOldFilesFinderConfig.defaultSkippedDirectoryNames`
/// / `defaultSkippedDirectoryExtensions`. This finder is about the user's
/// own large media/archives/downloads sitting around, not a general-purpose
/// disk scanner.
///
/// `ScanContext.roots` is treated the same way every detector in this repo
/// treats it: each entry is a "home directory" root to resolve the scoped
/// subdirectories against (defaulting to the real home directory when
/// empty). Production call sites pass an empty `roots` (or the user's real
/// home); tests pass one or more sandboxed temp directories laid out like a
/// home directory (`<temp>/Downloads/...`) so this logic can be exercised
/// without touching the real machine.
///
/// ## "Last used" evidence
/// This detector uses filesystem modification time (`mtime`) as its only
/// "last used" signal (`LastUsedEvidence.Source.filesystemMTime`).
/// `kMDItemLastUsedDate` via Spotlight (`.spotlightLastUsedDate`) would be a
/// meaningfully stronger signal — it reflects opens/reads, not just writes
/// (e.g. a video you watch repeatedly but never re-save keeps an old mtime)
/// — but is deferred as a documented follow-up rather than shelled out to
/// `mdls` under time pressure. A clean mtime-based baseline, honestly
/// labeled via `LastUsedEvidence.source`, is an accepted trade-off matching
/// how other detectors in this repo already handle the same limitation
/// (e.g. `DevToolsDetectors.NodeDetector`'s lockfile-mtime fallback).
public struct LargeOldFilesFinder: Detector {
    public let id = "core.largeOldFiles"
    public let displayName = "Large & Old Files"
    public let category: DetectorCategory = .largeAndOldFiles

    private let config: LargeOldFilesFinderConfig
    private let now: @Sendable () -> Date

    public init(
        config: LargeOldFilesFinderConfig = LargeOldFilesFinderConfig(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.config = config
        self.now = now
    }

    public func scan(context: ScanContext) async throws -> [ScanItem] {
        let homeRoots = context.roots.isEmpty ? [NSHomeDirectory()] : context.roots
        let scanRoots = homeRoots.flatMap { home in
            config.scopedDirectories.map { home + "/" + $0 }
        }

        let referenceDate = now()
        let limit = max(1, context.maxConcurrency)

        return await withTaskGroup(of: [ScanItem].self) { group in
            var results: [ScanItem] = []
            var iterator = scanRoots.makeIterator()

            func addNext() {
                guard !Task.isCancelled, let root = iterator.next() else { return }
                group.addTask {
                    scanRoot(root, referenceDate: referenceDate)
                }
            }

            for _ in 0..<limit { addNext() }
            while let items = await group.next() {
                results.append(contentsOf: items)
                addNext()
            }
            return results
        }
    }

    /// Walks a single scoped root (e.g. `<home>/Downloads`) and evaluates
    /// every regular file found under it. Synchronous and self-contained so
    /// it can run inside a `TaskGroup` child task.
    private func scanRoot(_ root: String, referenceDate: Date) -> [ScanItem] {
        guard LargeOldFilesFS.isDirectory(root) else { return [] }

        var items: [ScanItem] = []
        LargeOldFilesFS.walkFiles(
            under: root,
            maxDepth: config.maxDepth,
            skippingDirectoryNames: config.skippedDirectoryNames,
            skippingDirectoryExtensions: config.skippedDirectoryExtensions,
            includeHidden: config.includeHiddenFiles,
            isCancelled: { Task.isCancelled }
        ) { path in
            if let item = evaluate(path: path, referenceDate: referenceDate) {
                items.append(item)
            }
        }
        return items
    }

    /// Applies the size/age/type filters to a single file and, if it
    /// qualifies, builds the `ScanItem` for it. Returns `nil` for anything
    /// that doesn't qualify or couldn't be `stat`-ed.
    private func evaluate(path: String, referenceDate: Date) -> ScanItem? {
        guard let attrs = LargeOldFilesFS.regularFileAttributes(path) else { return nil }
        guard attrs.sizeBytes >= config.minimumSizeBytes else { return nil }

        let ext = (path as NSString).pathExtension
        let matchedTypes = LargeOldFileTypeCategory.categories(matchingExtension: ext)
        if let fileTypeFilter = config.fileTypeFilter {
            guard !matchedTypes.isDisjoint(with: fileTypeFilter) else { return nil }
        }

        var ageDays: Int?
        if let mtime = attrs.modificationDate {
            ageDays = max(0, Int(referenceDate.timeIntervalSince(mtime) / 86400))
        }

        if let minimumAgeDays = config.minimumAgeDays {
            guard let ageDays, ageDays >= minimumAgeDays else { return nil }
        }

        let lastUsed = attrs.modificationDate.map {
            LastUsedEvidence(date: $0, source: .filesystemMTime)
        }

        var reasonParts = [LargeOldFilesFormatting.size(attrs.sizeBytes)]
        if let ageDays {
            reasonParts.append("last modified \(LargeOldFilesFormatting.age(days: ageDays)) ago")
        }
        if config.fileTypeFilter != nil {
            let matchedNames = matchedTypes.map(\.rawValue).sorted().joined(separator: ", ")
            reasonParts.append("type: \(matchedNames)")
        }

        return ScanItem(
            path: path,
            sizeBytes: attrs.sizeBytes,
            sourceDetectorID: id,
            category: categoryLabel(matchedTypes: matchedTypes),
            lastUsed: lastUsed,
            reason: reasonParts.joined(separator: ", ")
        )
    }

    private func categoryLabel(matchedTypes: Set<LargeOldFileTypeCategory>) -> String {
        guard let primary = matchedTypes.sorted(by: { $0.rawValue < $1.rawValue }).first else {
            return "Large & Old Files"
        }
        return "Large & Old Files — \(primary.rawValue.capitalized)"
    }
}
