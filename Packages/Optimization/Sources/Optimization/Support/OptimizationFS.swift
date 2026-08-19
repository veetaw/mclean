import Foundation

/// Read-only filesystem helpers shared by this package, mirroring
/// `DevToolsDetectors.DevToolsFS`'s style but reimplemented locally so this
/// package doesn't take on a sibling package as a dependency (see
/// `ARCHITECTURE.md`, and `PowerUserInspectors.ExternalCommand`'s doc
/// comment for the same rationale applied elsewhere in this repo).
///
/// Every function here only *reads* metadata — nothing writes, moves, or
/// deletes anything, matching the read-only contract of
/// `CoreScanEngine.Detector`. A `FileManager` is always taken as a
/// default-valued parameter, never stored, so call sites stay `Sendable`.
enum OptimizationFS {
    static func exists(_ path: String, fileManager: FileManager = .default) -> Bool {
        fileManager.fileExists(atPath: path)
    }

    static func isDirectory(_ path: String, fileManager: FileManager = .default) -> Bool {
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    static func modificationDate(_ path: String, fileManager: FileManager = .default) -> Date? {
        (try? fileManager.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    /// Size of a single regular file, in bytes. `nil` if the file doesn't
    /// exist or its size can't be read — plist files are tiny, so this
    /// deliberately doesn't need `DevToolsFS.recursiveSize`'s directory-tree
    /// summation.
    static func fileSize(_ path: String, fileManager: FileManager = .default) -> Int64? {
        guard let attrs = try? fileManager.attributesOfItem(atPath: path) else { return nil }
        if let size = attrs[.size] as? Int64 { return size }
        return (attrs[.size] as? NSNumber)?.int64Value
    }

    /// Sorted, non-recursive directory listing. Returns `[]` for a path
    /// that doesn't exist or isn't readable, rather than throwing.
    static func directoryEntries(_ path: String, fileManager: FileManager = .default) -> [String] {
        (try? fileManager.contentsOfDirectory(atPath: path))?.sorted() ?? []
    }
}
