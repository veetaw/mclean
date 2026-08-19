import Foundation

/// A single node in a filesystem size tree: a file, a directory, or a
/// synthetic "N more items" aggregate folded together by
/// ``DirectorySizeTreeBuilder`` when a directory has more entries than it's
/// configured to break out individually.
///
/// Value type — `Sendable`, `Hashable`, and `Codable` — so a tree can be
/// built off the main actor (a real directory walk is not fast) and handed
/// to SwiftUI, cached, or round-tripped through disk without any bridging.
public struct DirectoryNode: Sendable, Hashable, Codable, Identifiable {
    public enum Kind: String, Sendable, Hashable, Codable {
        /// A regular file (or anything `FileManager` doesn't report as a
        /// directory — device files, sockets, etc. are treated the same
        /// way: a leaf with a size and no children).
        case file
        case directory
        /// A synthetic node folding together the smallest entries beyond
        /// `DirectorySizeTreeBuilder.maxChildrenPerDirectory`, so a
        /// directory with thousands of tiny files still renders as a
        /// handful of legible treemap tiles instead of thousands of
        /// invisible slivers. Does not correspond to a real filesystem
        /// path — `path` is a synthetic placeholder, never suitable for
        /// filesystem operations (e.g. "reveal in Finder").
        case aggregate
    }

    /// Absolute filesystem path. Doubles as `id` — unique within one tree by
    /// construction. For `.aggregate` nodes this is a synthetic, non-real
    /// path (see `Kind.aggregate`).
    public let path: String
    public let name: String
    public let kind: Kind
    /// Total size in bytes: the file's own size for `.file`; the recursive
    /// sum of every descendant for `.directory`/`.aggregate`.
    public let sizeBytes: Int64
    /// Child nodes, populated for `.directory` when the builder materialized
    /// them (bounded by `maxDepth`/`maxChildrenPerDirectory`). Always empty
    /// for `.file` and `.aggregate`.
    public let children: [DirectoryNode]

    public var id: String { path }

    public init(
        path: String,
        name: String,
        kind: Kind,
        sizeBytes: Int64,
        children: [DirectoryNode] = []
    ) {
        self.path = path
        self.name = name
        self.kind = kind
        self.sizeBytes = sizeBytes
        self.children = children
    }

    public var isDirectory: Bool { kind == .directory }

    /// A real, existable filesystem URL for this node — `nil` for
    /// `.aggregate` nodes, which have no corresponding path on disk (so
    /// callers know not to offer filesystem actions like "reveal in
    /// Finder" for them).
    public var url: URL? {
        kind == .aggregate ? nil : URL(fileURLWithPath: path)
    }

    /// Children sorted largest-first — the order the treemap and any list
    /// presentation should use.
    public var childrenBySizeDescending: [DirectoryNode] {
        children.sorted { $0.sizeBytes > $1.sizeBytes }
    }
}
