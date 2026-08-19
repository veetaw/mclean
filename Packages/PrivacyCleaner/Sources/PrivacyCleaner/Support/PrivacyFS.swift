import Foundation

/// Read-only filesystem helpers shared by every detector in this package.
///
/// Every function here only *reads* metadata — nothing writes, moves, or
/// deletes anything, matching the read-only contract of
/// `CoreScanEngine.Detector`. Detectors never store a `FileManager` instance
/// as a stored property (it would need to be `Sendable`); instead every call
/// site here takes one as a default-valued parameter, created fresh.
///
/// Mirrors `DevToolsDetectors.DevToolsFS` / `TrashCleaner.TrashFS` —
/// duplicated here rather than shared because `PrivacyCleaner` deliberately
/// depends only on `CoreScanEngine`, matching every other detector package
/// in this repo.
enum PrivacyFS {

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

    /// Sorted, non-recursive directory listing. Returns `[]` for a path that
    /// doesn't exist or isn't readable, rather than throwing.
    static func directoryEntries(_ path: String, fileManager: FileManager = .default) -> [String] {
        (try? fileManager.contentsOfDirectory(atPath: path))?.sorted() ?? []
    }

    /// Size, in bytes, of a single regular file. `nil` if it doesn't exist or
    /// isn't a regular file. Deliberately does not open/read the file's
    /// contents — only stats it, matching this package's strictly-opaque
    /// treatment of every cookie jar / history database it reports on.
    static func fileSize(_ path: String, fileManager: FileManager = .default) -> Int64? {
        guard let attrs = try? fileManager.attributesOfItem(atPath: path) else { return nil }
        if let size = attrs[.size] as? Int64 { return size }
        return (attrs[.size] as? NSNumber)?.int64Value
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
            return fileSize(path, fileManager: fileManager)
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
}
