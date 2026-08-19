import Foundation
import CoreScanEngine

/// Best-effort scan for Photos.app's "Recently Deleted" content inside a
/// `.photoslibrary` package (typically `~/Pictures/Photos Library.photoslibrary`,
/// though any `*.photoslibrary` package directly under `~/Pictures` is
/// considered, since a user can rename or relocate the default library
/// within `~/Pictures`).
///
/// ## Known limitations — read before trusting this detector
///
/// A `.photoslibrary` package's internal layout is a **private
/// implementation detail** of Photos.app, not a documented format. Modern
/// Photos (the Core Data/SQLite-backed library format used since macOS Big
/// Sur) tracks an asset's "trashed" status **inside its database**
/// (`database/Photos.sqlite`), not by relocating the asset's file to a
/// separate "Recently Deleted" folder on disk. In practice this means there
/// is usually **no filesystem-visible directory to find here at all** —
/// the original/derivative files for a trashed photo typically stay right
/// where they were, just flagged in the database.
///
/// This detector does **not** open, parse, or query the Photos SQLite
/// database — doing so would mean depending on Photos' private schema,
/// which is out of scope and unsafe to guess at. Instead it does a
/// best-effort **name-pattern** search (directories whose name suggests
/// "trash"/"recently deleted") within each library package, purely in case
/// a matching resource happens to be present on some macOS version. It is
/// expected and normal for this to return no items on most or all
/// libraries — that is treated as success, not failure.
///
/// If no `.photoslibrary` package is found under `~/Pictures`, or nothing
/// matches, this returns **no items** rather than guessing at the layout.
///
/// Strictly read-only. See `CoreScanEngine.Detector`.
public struct PhotosRecentlyDeletedDetector: Detector {
    public let id = "trash.photos"
    public let displayName = "Photos — Recently Deleted"
    public let category: DetectorCategory = .trash

    public init() {}

    public func scan(context: ScanContext) async throws -> [ScanItem] {
        var items: [ScanItem] = []

        for home in HomeDirectories.resolve(context) {
            if Task.isCancelled { break }
            let picturesRoot = home + "/Pictures"
            guard TrashFS.isDirectory(picturesRoot) else { continue }

            let libraries = TrashFS.directoryEntries(picturesRoot)
                .filter { $0.hasSuffix(".photoslibrary") }
                .map { picturesRoot + "/" + $0 }

            for library in libraries {
                if Task.isCancelled { break }
                items.append(contentsOf: scanLibrary(library))
            }
        }
        return items
    }

    private func scanLibrary(_ library: String) -> [ScanItem] {
        let libraryName = (library as NSString).lastPathComponent
        let matches = TrashFS.findDirectories(
            under: library,
            maxDepth: 4,
            isCancelled: { Task.isCancelled },
            matching: { name, _ in
                let lowered = name.lowercased()
                return lowered.contains("recentlydeleted")
                    || lowered.contains("recently deleted")
                    || lowered == "trash"
                    || lowered.hasSuffix(".trash")
            }
        )

        var items: [ScanItem] = []
        for path in matches {
            if Task.isCancelled { break }
            let name = (path as NSString).lastPathComponent
            items.append(ScanItem(
                path: path,
                sizeBytes: TrashFS.recursiveSize(of: path, isCancelled: { Task.isCancelled }),
                sourceDetectorID: "trash.photos.recently-deleted",
                category: "Photos — Recently Deleted",
                lastUsed: TrashFS.modificationDate(path).map { LastUsedEvidence(date: $0, source: .filesystemMTime) },
                reason: "'\(name)' inside \(libraryName) matched a Recently-Deleted-like name pattern. See PhotosRecentlyDeletedDetector's doc comment: Photos' internal layout is undocumented and usually tracks trashed items in its database rather than on disk, so this match should be verified before relying on it."
            ))
        }
        return items
    }
}
