import Foundation

/// Walks a directory tree, bottom-up, into a ``DirectoryNode`` — the data
/// source behind Space Lens's treemap.
///
/// Strictly read-only: every call here is a `FileManager`/`URL`
/// attribute-reading or listing call. Nothing is written, moved, or
/// deleted.
///
/// Bounded by construction so a real home directory (which can easily
/// contain hundreds of thousands of files) stays responsive rather than
/// triggering an unbounded, unthrottled full recursive walk:
///
/// - `maxDepth` caps how many levels below the root get their own children
///   materialized as distinct nodes. A directory reached at exactly
///   `maxDepth` still gets an accurate total size (via a fast,
///   node-budget-exempt recursive sum) but becomes a leaf in the tree —
///   the treemap stops subdividing there rather than continuing forever.
/// - `maxChildrenPerDirectory` caps how many entries of a single directory
///   become their own nodes. When a directory has more entries than that,
///   the largest `maxChildrenPerDirectory - 1` become individual nodes and
///   everything else is folded into one synthetic `.aggregate` node ("N
///   more items") — so a directory with thousands of small files still
///   renders as a handful of legible treemap tiles, not thousands of
///   invisible slivers.
/// - `maxNodesBudget` is a global ceiling on how many filesystem entries the
///   *entire* walk will materialize as nodes, across every directory
///   combined — a backstop against pathological trees (e.g. one directory
///   containing millions of files even after the per-directory cap) so a
///   single call can't run for an unbounded amount of time. Once exhausted,
///   remaining entries are simply omitted (undercounting size slightly)
///   rather than the walk hanging or crashing.
///
/// Every directory read tolerates permission errors and races (a file
/// deleted mid-walk, a directory that isn't readable, a broken symlink) by
/// skipping the offending entry rather than throwing — one unreadable
/// subdirectory never aborts the whole build. Symbolic links are never
/// followed, avoiding both double-counting and symlink loops.
public enum DirectorySizeTreeBuilder {
    /// Materializes up to 6 levels of individual nodes below the root
    /// (root itself at depth 0, so directories through depth 4 get their
    /// children broken out; anything at depth 5 becomes a leaf with an
    /// accurate rolled-up size). Deep enough to reach e.g.
    /// `~/Library/Caches/<app>/<subfolder>` as a distinct tile, shallow
    /// enough to stay fast on a real home directory.
    public static let defaultMaxDepth = 5
    /// Enough to show real structure (most directories have far fewer
    /// entries than this) while keeping every treemap level's tile count
    /// low enough to stay legible and cheap to lay out.
    public static let defaultMaxChildrenPerDirectory = 60
    /// A generous ceiling for a single home-directory scan — high enough
    /// to rarely bind in practice, low enough to guarantee the walk
    /// terminates promptly even against a pathological tree.
    public static let defaultMaxNodesBudget = 40_000

    /// Builds a size tree rooted at `root`. Returns `nil` if `isCancelled`
    /// is already true, if `root` doesn't exist, or if `root` is itself a
    /// symbolic link (never followed).
    public static func build(
        root: URL,
        maxDepth: Int = defaultMaxDepth,
        maxChildrenPerDirectory: Int = defaultMaxChildrenPerDirectory,
        maxNodesBudget: Int = defaultMaxNodesBudget,
        fileManager: FileManager = .default,
        isCancelled: @Sendable () -> Bool = { false }
    ) -> DirectoryNode? {
        guard !isCancelled() else { return nil }
        var budget = maxNodesBudget
        return node(
            at: root,
            depth: 0,
            maxDepth: maxDepth,
            maxChildrenPerDirectory: maxChildrenPerDirectory,
            budget: &budget,
            fileManager: fileManager,
            isCancelled: isCancelled
        )
    }

    private static func node(
        at url: URL,
        depth: Int,
        maxDepth: Int,
        maxChildrenPerDirectory: Int,
        budget: inout Int,
        fileManager: FileManager,
        isCancelled: @Sendable () -> Bool
    ) -> DirectoryNode? {
        if isCancelled() || budget <= 0 { return nil }

        guard let resourceValues = try? url.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]
        ) else {
            // Vanished mid-walk, or unreadable — skip it.
            return nil
        }
        if resourceValues.isSymbolicLink == true {
            return nil
        }

        let path = url.path
        let name = url.lastPathComponent
        budget -= 1

        guard resourceValues.isDirectory == true else {
            let size = Int64(resourceValues.fileSize ?? 0)
            return DirectoryNode(path: path, name: name, kind: .file, sizeBytes: size)
        }

        guard depth < maxDepth else {
            let size = quickRecursiveSize(of: path, fileManager: fileManager, isCancelled: isCancelled)
            return DirectoryNode(path: path, name: name, kind: .directory, sizeBytes: size)
        }

        guard let entries = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey],
            options: []
        ) else {
            // Unreadable directory (permissions, race) — treat as an empty
            // leaf rather than aborting the whole build.
            return DirectoryNode(path: path, name: name, kind: .directory, sizeBytes: 0)
        }

        var children: [DirectoryNode] = []
        children.reserveCapacity(min(entries.count, maxChildrenPerDirectory))
        for entry in entries {
            if isCancelled() || budget <= 0 { break }
            if let child = node(
                at: entry,
                depth: depth + 1,
                maxDepth: maxDepth,
                maxChildrenPerDirectory: maxChildrenPerDirectory,
                budget: &budget,
                fileManager: fileManager,
                isCancelled: isCancelled
            ) {
                children.append(child)
            }
        }

        if children.count > maxChildrenPerDirectory {
            children.sort { $0.sizeBytes > $1.sizeBytes }
            let keepCount = maxChildrenPerDirectory - 1
            let kept = Array(children.prefix(keepCount))
            let overflow = children[keepCount...]
            let overflowSize = overflow.reduce(Int64(0)) { $0 + $1.sizeBytes }
            let aggregate = DirectoryNode(
                path: path + "/.spacelens-more-items",
                name: "\(overflow.count) more items",
                kind: .aggregate,
                sizeBytes: overflowSize
            )
            children = kept + [aggregate]
        }

        let totalSize = children.reduce(Int64(0)) { $0 + $1.sizeBytes }
        return DirectoryNode(path: path, name: name, kind: .directory, sizeBytes: totalSize, children: children)
    }

    /// Fast recursive size-only sum (no per-entry node materialization, and
    /// deliberately exempt from `maxNodesBudget` — it never allocates a
    /// node per entry), used once `maxDepth` is reached so a directory's
    /// total is still accurate without spending the node budget
    /// subdividing further. Mirrors `DevToolsDetectors.DevToolsFS.recursiveSize`.
    private static func quickRecursiveSize(
        of path: String,
        fileManager: FileManager,
        isCancelled: @Sendable () -> Bool
    ) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: [],
            errorHandler: { _, _ in true }
        ) else { return 0 }

        var total: Int64 = 0
        var counter = 0
        for case let fileURL as URL in enumerator {
            counter += 1
            if counter.isMultiple(of: 256), isCancelled() { break }
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
