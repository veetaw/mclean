import CryptoKit
import Foundation

/// Read-only filesystem helpers shared by both detectors in this package.
///
/// Every function here only *reads* file bytes/metadata — nothing writes,
/// moves, or deletes anything, matching the read-only contract of
/// `CoreScanEngine.Detector`. Mirrors the style of
/// `DevToolsDetectors.DevToolsFS`, extended with file-content hashing since
/// this package (unlike `DevToolsDetectors`) needs to read file bytes, not
/// just metadata.
enum DuplicateFinderFS {

    static func isDirectory(_ path: String, fileManager: FileManager = .default) -> Bool {
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    static func fileSize(_ path: String, fileManager: FileManager = .default) -> Int64? {
        let attrs = try? fileManager.attributesOfItem(atPath: path)
        if let size = attrs?[.size] as? Int64 { return size }
        return (attrs?[.size] as? NSNumber)?.int64Value
    }

    static func modificationDate(_ path: String, fileManager: FileManager = .default) -> Date? {
        (try? fileManager.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    /// Recursively enumerates every regular file under `root` (or, if `root`
    /// is itself a regular file, just that one file), returning each one's
    /// path and size. Symbolic links and hidden files/directories are
    /// skipped — symlinks to avoid double-counting/loops, hidden entries
    /// (`.git`, `.DS_Store`, app support dot-directories, ...) because they
    /// are very rarely what a user means by "duplicate files in my
    /// Pictures/Downloads/Documents". Returns `[]` for a path that doesn't
    /// exist or isn't readable, rather than throwing.
    static func regularFiles(
        under root: String,
        fileManager: FileManager = .default,
        isCancelled: @Sendable () -> Bool = { false }
    ) -> [(path: String, size: Int64)] {
        guard fileManager.fileExists(atPath: root) else { return [] }
        guard isDirectory(root, fileManager: fileManager) else {
            guard let size = fileSize(root, fileManager: fileManager) else { return [] }
            return [(root, size)]
        }

        let url = URL(fileURLWithPath: root)
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else { return [] }

        var results: [(path: String, size: Int64)] = []
        var counter = 0
        while let fileURL = enumerator.nextObject() as? URL {
            counter += 1
            if counter.isMultiple(of: 256), isCancelled() { break }
            guard let values = try? fileURL.resourceValues(
                forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
            ) else { continue }
            if values.isSymbolicLink == true { continue }
            guard values.isRegularFile == true, let size = values.fileSize else { continue }
            results.append((fileURL.path, Int64(size)))
        }
        return results
    }

    /// Streams the file at `path` through SHA-256 in fixed-size chunks
    /// (default 1 MiB) so hashing a large file never requires holding the
    /// whole thing in memory at once. Returns `nil` if the file can't be
    /// opened/read (permission denied, deleted mid-scan, etc.) or if
    /// cancelled partway through — a partial hash would be worse than none.
    static func sha256Hex(
        ofFileAt path: String,
        chunkSize: Int = 1 << 20,
        isCancelled: @Sendable () -> Bool = { false }
    ) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            if isCancelled() { return nil }
            guard let chunk = try? handle.read(upToCount: chunkSize), !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Computes `sha256Hex(ofFileAt:)` for several paths, bounded to at most
    /// `maxConcurrency` concurrent tasks — hashing many large files
    /// unboundedly-concurrently would be real disk/CPU contention, not just
    /// a style nicety. Stops scheduling new work once the current `Task` is
    /// cancelled (already-scheduled work still completes and is returned).
    static func sha256Hashes(
        ofFilesAt paths: [String],
        maxConcurrency: Int
    ) async -> [String: String] {
        guard !paths.isEmpty else { return [:] }
        let limit = max(1, maxConcurrency)

        return await withTaskGroup(of: (String, String?).self) { group in
            var results: [String: String] = [:]
            var iterator = paths.makeIterator()

            func addNext() {
                guard !Task.isCancelled, let next = iterator.next() else { return }
                group.addTask {
                    (next, sha256Hex(ofFileAt: next, isCancelled: { Task.isCancelled }))
                }
            }

            for _ in 0..<limit { addNext() }
            while let (path, hash) = await group.next() {
                if let hash { results[path] = hash }
                addNext()
            }
            return results
        }
    }
}
