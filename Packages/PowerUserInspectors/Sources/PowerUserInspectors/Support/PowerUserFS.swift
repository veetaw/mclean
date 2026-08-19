import Foundation

/// Read-only filesystem helpers shared across this package, mirroring the
/// pattern used by `DevToolsDetectors.DevToolsFS` and
/// `MobileDevDetectors.FSUtil`. Deliberately re-implemented locally rather
/// than depending on either sibling package (see `ARCHITECTURE.md` — this
/// module intentionally keeps its dependency footprint narrow: only
/// `CoreScanEngine` and `PrivilegedHelperXPC`).
///
/// Every function here only reads metadata — nothing writes, moves, or
/// deletes anything.
enum PowerUserFS {
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

    /// Size, in bytes, of a single regular file. `nil` if `path` doesn't
    /// exist or isn't a regular file (use `recursiveSize` for directories).
    static func fileSize(_ path: String, fileManager: FileManager = .default) -> Int64? {
        guard let attrs = try? fileManager.attributesOfItem(atPath: path) else { return nil }
        if let size = attrs[.size] as? Int64 { return size }
        return (attrs[.size] as? NSNumber)?.int64Value
    }

    /// Sorted, non-recursive directory listing. Returns `[]` for a path that
    /// doesn't exist or isn't readable, rather than throwing.
    static func directoryEntries(_ path: String, fileManager: FileManager = .default) -> [String] {
        (try? fileManager.contentsOfDirectory(atPath: path))?.sorted() ?? []
    }

    /// Canonical, symlink-resolved absolute path via the C `realpath(3)`
    /// call, or `nil` if `path` doesn't exist (matching `realpath`'s own
    /// contract — it requires every path component to exist). Unlike
    /// `URL.standardizedFileURL`/`NSString.standardizingPath`, this is a
    /// direct `realpath(3)` call rather than a heuristic that only fires
    /// for a handful of well-known symlinks — callers that need consistent
    /// normalization for a path that might not exist yet should resolve an
    /// existing ancestor directory instead (see
    /// `ConfigFileExplorer.canonicalPath(_:)`).
    static func realpath(_ path: String) -> String? {
        var buffer = [UInt8](repeating: 0, count: Int(PATH_MAX))
        let result: UnsafeMutablePointer<CChar>? = buffer.withUnsafeMutableBytes { rawBuffer in
            Foundation.realpath(path, rawBuffer.bindMemory(to: CChar.self).baseAddress)
        }
        guard result != nil else { return nil }
        let nullTerminatorIndex = buffer.firstIndex(of: 0) ?? buffer.count
        return String(decoding: buffer[..<nullTerminatorIndex], as: UTF8.self)
    }

    /// Recursively sums the size of every regular file under `path` (or, if
    /// `path` is itself a regular file, its size). Symbolic links are not
    /// followed. Returns `nil` only when `path` doesn't exist at all.
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
