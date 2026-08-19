import Foundation

/// Read-only filesystem helpers used only inside this package.
///
/// Deliberately re-implemented locally rather than depending on
/// `PowerUserInspectors`'s own `PowerUserFS` (which is `internal` to that
/// module and not exported) — this mirrors the pattern already used by
/// `PowerUserInspectors.PowerUserFS` itself (whose doc comment notes it is
/// "deliberately re-implemented locally rather than depending on either
/// sibling package"), and by `DevToolsDetectors.DevToolsFS` /
/// `MobileDevDetectors.FSUtil`.
///
/// Every function here only reads metadata — nothing writes, moves, or
/// deletes anything. This whole package is read-only by design; see
/// `UninstallerService`'s doc comment for the enforced boundary.
enum UninstallerFS {
    static func exists(_ path: String, fileManager: FileManager = .default) -> Bool {
        fileManager.fileExists(atPath: path)
    }

    static func isDirectory(_ path: String, fileManager: FileManager = .default) -> Bool {
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    /// Sorted, non-recursive directory listing. Returns `[]` for a path that
    /// doesn't exist or isn't readable, rather than throwing.
    static func directoryEntries(_ path: String, fileManager: FileManager = .default) -> [String] {
        (try? fileManager.contentsOfDirectory(atPath: path))?.sorted() ?? []
    }

    /// Size, in bytes, of a single regular file. `nil` if `path` doesn't
    /// exist or isn't a regular file (use `recursiveSize` for directories).
    static func fileSize(_ path: String, fileManager: FileManager = .default) -> Int64? {
        guard let attrs = try? fileManager.attributesOfItem(atPath: path) else { return nil }
        if let size = attrs[.size] as? Int64 { return size }
        return (attrs[.size] as? NSNumber)?.int64Value
    }

    /// Recursively sums the size of every regular file under `path` (or, if
    /// `path` is itself a regular file, its size). Symbolic links are not
    /// followed. Returns `nil` only when `path` doesn't exist at all.
    static func recursiveSize(of path: String, fileManager: FileManager = .default) -> Int64? {
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
