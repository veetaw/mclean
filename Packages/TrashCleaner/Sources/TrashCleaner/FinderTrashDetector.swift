import Foundation
import CoreScanEngine
#if canImport(Darwin)
import Darwin
#endif

/// Finds items sitting in Finder's Trash: the boot volume's per-user trash
/// (`~/.Trash`) and, for every currently-mounted external volume, that
/// volume's per-user trash (`/Volumes/<Name>/.Trashes/<uid>`).
///
/// Each *top-level item* inside a trash directory is reported as its own
/// `ScanItem` — not the whole Trash folder as one blob — so the UI can show
/// what's actually sitting in there and let the user pick and choose.
///
/// Strictly read-only. See `CoreScanEngine.Detector`.
public struct FinderTrashDetector: Detector {
    public let id = "trash.finder"
    public let displayName = "Finder Trash"
    public let category: DetectorCategory = .trash

    /// Candidate external-volume mount points to check for a
    /// `.Trashes/<uid>` subdirectory. Defaults to the real currently-mounted
    /// volumes (`TrashFS.realMountedVolumeRoots`); tests inject a fixed list
    /// of temp directories standing in for `/Volumes/<Name>` so this
    /// detector never touches real removable media during a test run.
    private let mountedVolumeRoots: @Sendable () -> [String]

    public init(mountedVolumeRoots: @escaping @Sendable () -> [String] = TrashFS.realMountedVolumeRoots) {
        self.mountedVolumeRoots = mountedVolumeRoots
    }

    public func scan(context: ScanContext) async throws -> [ScanItem] {
        var items: [ScanItem] = []

        for home in HomeDirectories.resolve(context) {
            if Task.isCancelled { break }
            items.append(contentsOf: scanTrashDirectory(
                home + "/.Trash",
                sourceDetectorID: "trash.finder.boot-volume",
                locationLabel: "Finder Trash (boot volume)"
            ))
        }

        let uid = getuid()
        for volumeRoot in mountedVolumeRoots() {
            if Task.isCancelled { break }
            let volumeName = (volumeRoot as NSString).lastPathComponent
            items.append(contentsOf: scanTrashDirectory(
                volumeRoot + "/.Trashes/\(uid)",
                sourceDetectorID: "trash.finder.external-volume",
                locationLabel: "Finder Trash (\(volumeName))"
            ))
        }

        return items
    }

    private func scanTrashDirectory(
        _ trashPath: String,
        sourceDetectorID: String,
        locationLabel: String
    ) -> [ScanItem] {
        guard TrashFS.isDirectory(trashPath) else { return [] }

        var items: [ScanItem] = []
        for entry in TrashFS.directoryEntries(trashPath) {
            if Task.isCancelled { break }
            // Finder/OS bookkeeping noise, not something the user put in
            // the Trash — not worth surfacing as a "trash item".
            if entry == ".DS_Store" { continue }

            let path = trashPath + "/" + entry
            items.append(ScanItem(
                path: path,
                sizeBytes: TrashFS.recursiveSize(of: path, isCancelled: { Task.isCancelled }),
                sourceDetectorID: sourceDetectorID,
                category: "Trash — \(locationLabel)",
                lastUsed: TrashFS.modificationDate(path).map { LastUsedEvidence(date: $0, source: .filesystemMTime) },
                reason: "'\(entry)' is sitting in \(locationLabel) at \(trashPath) — already moved to the Trash by the user or Finder."
            ))
        }
        return items
    }
}
