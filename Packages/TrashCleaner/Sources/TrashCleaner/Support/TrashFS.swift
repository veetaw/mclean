import Foundation

/// Read-only filesystem helpers shared by every detector in this package.
///
/// Every function here only *reads* metadata — nothing writes, moves, or
/// deletes anything, matching the read-only contract of
/// `CoreScanEngine.Detector`. Detectors never store a `FileManager` instance
/// as a stored property (it would need to be `Sendable`); instead every call
/// site here takes one as a default-valued parameter, created fresh.
///
/// Mirrors `DevToolsDetectors.DevToolsFS` — duplicated here rather than
/// shared because `TrashCleaner` deliberately depends only on
/// `CoreScanEngine`, matching every other detector package in this repo.
///
/// The enum itself is `public` only because `realMountedVolumeRoots()`
/// below needs to be usable as a public default-argument value from
/// `FinderTrashDetector.init`; every member besides that one stays at the
/// narrowest access level it can (this is a scan-support helper, not a
/// package API surface).
public enum TrashFS {

    static func isDirectory(_ path: String, fileManager: FileManager = .default) -> Bool {
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    static func exists(_ path: String, fileManager: FileManager = .default) -> Bool {
        fileManager.fileExists(atPath: path)
    }

    static func isSymbolicLink(_ path: String, fileManager: FileManager = .default) -> Bool {
        let attrs = try? fileManager.attributesOfItem(atPath: path)
        return (attrs?[.type] as? FileAttributeType) == .typeSymbolicLink
    }

    static func modificationDate(_ path: String, fileManager: FileManager = .default) -> Date? {
        (try? fileManager.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    /// Sorted, non-recursive directory listing. Returns `[]` for a path that
    /// doesn't exist or isn't readable, rather than throwing.
    static func directoryEntries(_ path: String, fileManager: FileManager = .default) -> [String] {
        (try? fileManager.contentsOfDirectory(atPath: path))?.sorted() ?? []
    }

    /// Recursively sums the size of every regular file under `path` (or, if
    /// `path` is itself a regular file, its size). Symbolic links are not
    /// followed (avoids double-counting and symlink loops). Returns `nil`
    /// only when `path` doesn't exist at all.
    static func recursiveSize(
        of path: String,
        fileManager: FileManager = .default,
        isCancelled: @Sendable () -> Bool = { false }
    ) -> Int64? {
        guard exists(path, fileManager: fileManager) else { return nil }
        guard isDirectory(path, fileManager: fileManager) else {
            let attrs = try? fileManager.attributesOfItem(atPath: path)
            return (attrs?[.size] as? Int64) ?? (attrs?[.size] as? NSNumber)?.int64Value
        }

        let url = URL(fileURLWithPath: path)
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: [],
            errorHandler: { _, _ in true }
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if isCancelled() { break }
            guard let values = try? fileURL.resourceValues(
                forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
            ) else { continue }
            if values.isSymbolicLink == true { continue }
            if values.isRegularFile == true, let size = values.fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    /// Bounded recursive search for directories matching `predicate`, used to
    /// find things like Mail.app trash mailboxes or Photos "recently
    /// deleted" resources by name pattern without walking an entire
    /// directory tree unboundedly.
    ///
    /// Matched directories are not descended into further (so a matched
    /// `.mbox` doesn't get double-reported via anything matching further
    /// inside it). Directories named in `skipNames`, and symbolic links, are
    /// never descended into either.
    static func findDirectories(
        under root: String,
        maxDepth: Int,
        skipping skipNames: Set<String> = [],
        fileManager: FileManager = .default,
        isCancelled: @Sendable () -> Bool = { false },
        matching predicate: @Sendable (_ name: String, _ path: String) -> Bool
    ) -> [String] {
        var results: [String] = []

        func walk(_ path: String, depth: Int) {
            if isCancelled() || depth > maxDepth { return }
            guard let entries = try? fileManager.contentsOfDirectory(atPath: path) else { return }
            for entry in entries {
                if isCancelled() { return }
                let full = path + "/" + entry
                guard isDirectory(full, fileManager: fileManager) else { continue }
                if predicate(entry, full) {
                    results.append(full)
                    continue
                }
                if skipNames.contains(entry) { continue }
                if isSymbolicLink(full, fileManager: fileManager) { continue }
                walk(full, depth: depth + 1)
            }
        }

        walk(root, depth: 0)
        return results.sorted()
    }

    /// Currently-mounted volume root paths (e.g. `/Volumes/Backup Drive`),
    /// excluding the boot volume itself and hidden system volumes. Used as
    /// the default source of candidate `.Trashes/<uid>` locations for
    /// `FinderTrashDetector`; tests inject a fixed list instead so they never
    /// depend on what's actually mounted on the machine running the test.
    ///
    /// `public` (rather than the package-internal default used by the rest
    /// of this type) only because it's referenced as a default argument
    /// value from `FinderTrashDetector.init`, which requires the same or
    /// looser access level.
    public static func realMountedVolumeRoots() -> [String] {
        guard let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeIsRootFileSystemKey],
            options: [.skipHiddenVolumes]
        ) else { return [] }
        return urls.map(\.path).filter { $0 != "/" }
    }
}
