import Foundation

/// Read-only filesystem helpers for `LargeOldFilesFinder`, mirroring the
/// bounded, symlink-safe, cancellation-aware walking pattern established by
/// `DevToolsDetectors.DevToolsFS`. Kept package-local rather than shared
/// across packages, matching how each detector package in this repo already
/// owns its own small copy of these primitives instead of introducing a new
/// cross-package dependency for a handful of `FileManager` calls.
///
/// Nothing here writes, moves, or deletes anything — only `stat` and
/// directory listings, matching the read-only contract of
/// `CoreScanEngine.Detector`. No `FileManager` instance is ever stored as a
/// property; every call site takes one as a default-valued parameter,
/// created fresh (relevant under Swift 6 strict concurrency, since
/// `FileManager` is not `Sendable`).
enum LargeOldFilesFS {

    static func isDirectory(_ path: String, fileManager: FileManager = .default) -> Bool {
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    static func isSymbolicLink(_ path: String, fileManager: FileManager = .default) -> Bool {
        let attrs = try? fileManager.attributesOfItem(atPath: path)
        return (attrs?[.type] as? FileAttributeType) == .typeSymbolicLink
    }

    /// The subset of a regular file's metadata this finder cares about.
    struct FileAttributes {
        let sizeBytes: Int64
        let modificationDate: Date?
    }

    /// Returns `nil` for anything that isn't a plain regular file (including
    /// directories and symlinks) or that couldn't be `stat`-ed.
    static func regularFileAttributes(_ path: String, fileManager: FileManager = .default) -> FileAttributes? {
        guard let attrs = try? fileManager.attributesOfItem(atPath: path) else { return nil }
        guard (attrs[.type] as? FileAttributeType) == .typeRegular else { return nil }
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let date = attrs[.modificationDate] as? Date
        return FileAttributes(sizeBytes: size, modificationDate: date)
    }

    /// Bounded, depth-limited, symlink-safe recursive walk over every
    /// *regular file* under `root`, invoking `visit` with each file's full
    /// path.
    ///
    /// - Never follows symbolic links (avoids loops and double-counting).
    /// - Never descends into a directory whose name is in
    ///   `skippingDirectoryNames` (territory owned by other detectors, e.g.
    ///   `node_modules`, `.git`, `Library`) or whose extension is in
    ///   `skippingDirectoryExtensions` (bundles/packages such as `.app`,
    ///   treated as opaque leaves rather than walked file-by-file).
    /// - Skips dotfiles/dot-directories unless `includeHidden` is `true`.
    /// - Silently stops descending into a directory it can't read (permission
    ///   denied, race with deletion, ...) rather than throwing.
    /// - Checks `isCancelled()` before processing every entry so a long walk
    ///   over a large directory tree can be aborted promptly.
    static func walkFiles(
        under root: String,
        maxDepth: Int,
        skippingDirectoryNames: Set<String>,
        skippingDirectoryExtensions: Set<String>,
        includeHidden: Bool,
        fileManager: FileManager = .default,
        isCancelled: @Sendable () -> Bool = { false },
        visit: (_ path: String) -> Void
    ) {
        func walk(_ path: String, depth: Int) {
            if isCancelled() || depth > maxDepth { return }
            guard let entries = try? fileManager.contentsOfDirectory(atPath: path) else { return }
            for entry in entries {
                if isCancelled() { return }
                if !includeHidden && entry.hasPrefix(".") { continue }
                let full = path + "/" + entry
                if isSymbolicLink(full, fileManager: fileManager) { continue }
                if isDirectory(full, fileManager: fileManager) {
                    if skippingDirectoryNames.contains(entry) { continue }
                    let ext = (entry as NSString).pathExtension.lowercased()
                    if !ext.isEmpty && skippingDirectoryExtensions.contains(ext) { continue }
                    walk(full, depth: depth + 1)
                } else {
                    visit(full)
                }
            }
        }
        walk(root, depth: 0)
    }
}
