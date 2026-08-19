import Foundation

/// Read-only filesystem helpers shared by every detector in this package,
/// mirroring `DevToolsDetectors.DevToolsFS`'s style (this package doesn't
/// depend on `DevToolsDetectors`, so the small set of helpers actually
/// needed here is duplicated rather than shared).
///
/// Every function here only *reads* metadata — nothing writes, moves, or
/// deletes anything, matching the read-only contract of
/// `CoreScanEngine.Detector`. Detectors never store a `FileManager` instance
/// as a stored property (it would need to be `Sendable`); instead every call
/// site here takes one as a default-valued parameter, created fresh.
///
/// Every listing/attribute read uses `try?` (or an enumerator error handler
/// that always continues), so an unreadable entry — including `EACCES`/
/// `EPERM` on a permission-restricted directory — is treated as "skip this
/// entry", never a thrown error or crash.
enum CacheCleanerFS {

    static func isDirectory(_ path: String, fileManager: FileManager = .default) -> Bool {
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    static func exists(_ path: String, fileManager: FileManager = .default) -> Bool {
        fileManager.fileExists(atPath: path)
    }

    static func modificationDate(_ path: String, fileManager: FileManager = .default) -> Date? {
        (try? fileManager.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    static func fileSize(_ path: String, fileManager: FileManager = .default) -> Int64? {
        let attrs = try? fileManager.attributesOfItem(atPath: path)
        return (attrs?[.size] as? Int64) ?? (attrs?[.size] as? NSNumber)?.int64Value
    }

    /// Sorted, non-recursive directory listing. Returns `[]` for a path that
    /// doesn't exist or isn't readable (including permission errors) rather
    /// than throwing.
    static func directoryEntries(_ path: String, fileManager: FileManager = .default) -> [String] {
        (try? fileManager.contentsOfDirectory(atPath: path))?.sorted() ?? []
    }

    /// Recursively sums the size of every regular file under `path` (or, if
    /// `path` is itself a regular file, its size). Convenience wrapper
    /// around `recursiveSizeAndLatestModification` for call sites that only
    /// need the size.
    static func recursiveSize(
        of path: String,
        fileManager: FileManager = .default,
        isCancelled: @Sendable () -> Bool = { false }
    ) -> Int64? {
        recursiveSizeAndLatestModification(of: path, fileManager: fileManager, isCancelled: isCancelled).size
    }

    /// A single-pass recursive walk of `path` that returns both the total
    /// size of every regular file underneath it *and* the most recent
    /// modification date found anywhere in the tree (including `path`
    /// itself, and every file/directory inside it).
    ///
    /// Using the latest mtime found *anywhere inside* a directory — not just
    /// the directory entry's own top-level mtime — matters for staleness
    /// checks: a directory's own mtime only updates when its *direct*
    /// children are added or removed, not when an existing file somewhere
    /// inside it is appended to. A plain top-level mtime check can therefore
    /// wrongly call an actively-written log directory or a temp directory an
    /// active process is still using "stale". This is the primary safety
    /// mechanism `TempFilesDetector` relies on to avoid flagging temp
    /// directories currently in use.
    ///
    /// Symbolic links are not followed (avoids double-counting and symlink
    /// loops). Unreadable entries (permission errors, entries that vanish
    /// mid-walk) are silently skipped, never thrown. Returns `(nil, nil)`
    /// only when `path` doesn't exist at all.
    static func recursiveSizeAndLatestModification(
        of path: String,
        fileManager: FileManager = .default,
        isCancelled: @Sendable () -> Bool = { false }
    ) -> (size: Int64?, latestModification: Date?) {
        guard exists(path, fileManager: fileManager) else { return (nil, nil) }
        guard isDirectory(path, fileManager: fileManager) else {
            return (fileSize(path, fileManager: fileManager), modificationDate(path, fileManager: fileManager))
        }

        var total: Int64 = 0
        var latest = modificationDate(path, fileManager: fileManager)

        let url = URL(fileURLWithPath: path)
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [
                .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey
            ],
            options: [],
            errorHandler: { _, _ in true }
        ) else { return (0, latest) }

        for case let fileURL as URL in enumerator {
            if isCancelled() { break }
            guard let values = try? fileURL.resourceValues(forKeys: [
                .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey
            ]) else { continue }
            if values.isSymbolicLink == true { continue }
            if values.isRegularFile == true, let size = values.fileSize {
                total += Int64(size)
            }
            if let modified = values.contentModificationDate, latest == nil || modified > latest! {
                latest = modified
            }
        }
        return (total, latest)
    }
}
