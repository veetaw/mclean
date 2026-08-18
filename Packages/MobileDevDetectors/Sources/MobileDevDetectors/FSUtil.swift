import Foundation

/// Internal, strictly read-only filesystem helpers shared by every detector
/// in this package. Nothing here writes, moves, or deletes anything — only
/// `stat`, directory listings, and (for plist-based metadata) reading small
/// files.
public enum FSUtil {
    /// Best-effort recursive size of everything under `url`, in bytes.
    /// Returns `nil` if the path does not exist. Periodically checks
    /// `Task.isCancelled` so callers walking many/large trees can bail out
    /// early without throwing (a partial size is still useful for callers
    /// that just want an order-of-magnitude figure).
    static func directorySize(at url: URL) async -> Int64? {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return nil }

        if !isDir.boolValue {
            let attrs = try? fm.attributesOfItem(atPath: url.path)
            return (attrs?[.size] as? NSNumber)?.int64Value
        }

        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        var counter = 0
        // `FileManager.DirectoryEnumerator`'s `Sequence`/`for-in` conformance
        // (via `NSEnumerator.makeIterator()`) is unavailable from async
        // contexts under Swift 6 strict concurrency, so drive it manually
        // with `nextObject()` instead.
        while let fileURL = enumerator.nextObject() as? URL {
            counter += 1
            if counter.isMultiple(of: 256), Task.isCancelled { break }
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let size = values.fileSize else { continue }
            total += Int64(size)
        }
        return total
    }

    /// Computes `directorySize(at:)` for several URLs, bounded to at most
    /// `maxConcurrency` concurrent tasks. Stops scheduling new work once the
    /// current `Task` is cancelled (already-scheduled work still completes).
    static func sizes(of urls: [URL], maxConcurrency: Int) async -> [URL: Int64] {
        guard !urls.isEmpty else { return [:] }
        let limit = max(1, maxConcurrency)

        return await withTaskGroup(of: (URL, Int64?).self) { group in
            var results: [URL: Int64] = [:]
            var iterator = urls.makeIterator()

            func addNext() {
                guard !Task.isCancelled, let next = iterator.next() else { return }
                group.addTask {
                    (next, await directorySize(at: next))
                }
            }

            for _ in 0..<limit { addNext() }
            while let (url, size) = await group.next() {
                if let size { results[url] = size }
                addNext()
            }
            return results
        }
    }

    static func modificationDate(ofItemAt path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    /// Latest modification date among `candidates` that actually exist
    /// on disk (each may be a file or a directory). Used to pick the
    /// strongest available mtime-based proxy among several files that
    /// could indicate "last real use".
    static func latestModificationDate(among candidates: [String]) -> Date? {
        candidates.compactMap(modificationDate(ofItemAt:)).max()
    }

    static func exists(atPath path: String, isDirectory: Bool? = nil) -> Bool {
        var isDir: ObjCBool = false
        let found = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        guard found else { return false }
        if let isDirectory { return isDir.boolValue == isDirectory }
        return true
    }

    /// Non-recursive listing of a directory's immediate subdirectories,
    /// ignoring dotfiles. Returns `[]` if `url` does not exist or isn't a
    /// directory — never throws, so detectors degrade gracefully when a
    /// toolchain isn't installed.
    static func subdirectories(of url: URL) -> [URL] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return entries.filter { entry in
            (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        }
    }

    /// Immediate child entries (files or directories) of `url` whose name
    /// starts with `prefix`. Used to resolve glob-like patterns such as
    /// `AndroidStudio*` without pulling in a globbing dependency.
    static func entries(in parent: URL, namePrefix prefix: String) -> [URL] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: parent,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return entries.filter { $0.lastPathComponent.hasPrefix(prefix) }
    }

    public static func homeDirectory() -> String {
        FileManager.default.homeDirectoryForCurrentUser.path
    }

    /// Parses a directory/version-like name into comparable numeric
    /// components, e.g. "android-33" -> [33], "34.0.0" -> [34, 0, 0],
    /// "gradle-8.4-bin" -> [8, 4]. Returns `nil` if no digits are found.
    static func versionComponents(from name: String, strippingPrefixes prefixes: [String] = []) -> [Int]? {
        var working = name
        for prefix in prefixes where working.hasPrefix(prefix) {
            working.removeFirst(prefix.count)
            break
        }
        // Keep only digits and separators so "gradle-8.4-bin" -> "8.4".
        let allowed = Set("0123456789.")
        let cleaned = String(working.map { allowed.contains($0) ? $0 : "." })
        let numbers = cleaned
            .split(separator: ".")
            .compactMap { Int($0) }
        return numbers.isEmpty ? nil : numbers
    }
}

/// Lexicographic comparison so `[Int]` version components compare the way
/// version numbers should ("2.0" > "1.9.9").
func versionArrayLess(_ lhs: [Int], _ rhs: [Int]) -> Bool {
    for (l, r) in zip(lhs, rhs) where l != r {
        return l < r
    }
    return lhs.count < rhs.count
}
