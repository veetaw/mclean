import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Walks a directory tree, bottom-up, into a ``DirectoryNode`` — the data
/// source behind Space Lens's treemap.
///
/// Strictly read-only: every call here is a `FileManager`/`URL`
/// attribute-reading or listing call. Nothing is written, moved, or
/// deleted. (This module never deletes anything, full stop — see
/// `SpaceLensView`'s header comment. Any future delete/quarantine action
/// belongs in `MainAppUI`'s `SafetyRules`/`QuarantineConfirmationSheet`
/// pipeline, not a shortcut invented here.)
///
/// Bounded by construction so a real home directory — or, now that
/// `SpaceLensView`'s default root is the whole boot volume ("/"), an
/// entire disk, which can easily contain millions of files — stays
/// responsive rather than triggering an unbounded, unthrottled full
/// recursive walk:
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
///   every remaining sibling — at whatever level of the walk the budget ran
///   out — falls back to the same cheap, budget-exempt total-size-only leaf
///   used for `maxDepth`, rather than being silently omitted. That keeps
///   every ancestor's reported size accurate (an omitted-but-unsized entry
///   would quietly undercount its parent, which matters far more once the
///   root is an entire disk than it did for a single home directory) while
///   still bounding total work; the user can drill into any such leaf later
///   to trigger a fresh, deeper, budget-refreshed scan (see
///   `SpaceLensView.drillDown(_:)`).
///
/// Every directory read tolerates permission errors and races (a file
/// deleted mid-walk, a directory that isn't readable, a broken symlink) by
/// skipping the offending entry rather than throwing — one unreadable
/// subdirectory never aborts the whole build. This matters even more at
/// whole-volume scale: walking from "/" hits many root-owned/SIP-protected
/// directories (e.g. under `/private/var/db`) this app has no permission to
/// read, and each one must resolve to a cheap, immediate "empty leaf"
/// rather than any kind of retry or slow failure path. Symbolic links are
/// never followed, which avoids both double-counting *and* symlink loops
/// (an infinite loop would otherwise be possible via a self-referential or
/// mutually-referential symlink chain) — a directory is only ever recursed
/// into after confirming it is a real directory and not a symbolic link.
///
/// Also never double-counts across mount-point boundaries — see
/// ``MountPointGuard`` below for why that specifically matters when the
/// root is "/".
public enum DirectorySizeTreeBuilder {
    /// Materializes up to 6 levels of individual nodes below the root
    /// (root itself at depth 0, so directories through depth 4 get their
    /// children broken out; anything at depth 5 becomes a leaf with an
    /// accurate rolled-up size). Deep enough to reach e.g.
    /// `~/Library/Caches/<app>/<subfolder>` as a distinct tile, shallow
    /// enough to stay fast on a real home directory or the boot volume.
    public static let defaultMaxDepth = 5
    /// Enough to show real structure (most directories have far fewer
    /// entries than this) while keeping every treemap level's tile count
    /// low enough to stay legible and cheap to lay out.
    public static let defaultMaxChildrenPerDirectory = 60
    /// A generous ceiling for a single scan — high enough to show real
    /// structure across an entire boot volume's many top-level directories
    /// (not just whichever one happens to be enumerated first), low enough
    /// to guarantee the walk terminates promptly even against a
    /// pathological tree. Budget exhaustion degrades gracefully (see the
    /// type doc comment above), so this is a performance/detail knob, not
    /// a correctness one.
    public static let defaultMaxNodesBudget = 120_000

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
        build(
            root: root,
            maxDepth: maxDepth,
            maxChildrenPerDirectory: maxChildrenPerDirectory,
            maxNodesBudget: maxNodesBudget,
            fileManager: fileManager,
            isCancelled: isCancelled,
            volumeGuard: MountPointGuard(rootPath: root.path)
        )
    }

    /// Same as the public `build` above, but with the `MountPointGuard`
    /// injectable — an internal (not `public`) seam that exists purely so
    /// `DirectorySizeTreeBuilderTests` can drive the mount-point dedup
    /// logic end-to-end (a synthetic device/container map standing in for a
    /// second real volume) via `@testable import`, without changing the
    /// public API surface real callers see.
    static func build(
        root: URL,
        maxDepth: Int = defaultMaxDepth,
        maxChildrenPerDirectory: Int = defaultMaxChildrenPerDirectory,
        maxNodesBudget: Int = defaultMaxNodesBudget,
        fileManager: FileManager = .default,
        isCancelled: @Sendable () -> Bool = { false },
        volumeGuard: MountPointGuard
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
            isCancelled: isCancelled,
            volumeGuard: volumeGuard
        )
    }

    private static func node(
        at url: URL,
        depth: Int,
        maxDepth: Int,
        maxChildrenPerDirectory: Int,
        budget: inout Int,
        fileManager: FileManager,
        isCancelled: @Sendable () -> Bool,
        volumeGuard: MountPointGuard
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

        guard volumeGuard.allowsDescending(into: path) else {
            // A duplicate path onto a volume already accounted for
            // elsewhere in this same walk (see `MountPointGuard`), or a
            // separate external/network volume out of scope for a default
            // boot-volume scan. Represented as an empty directory rather
            // than omitted from its parent's children entirely, so the
            // tree stays structurally complete (e.g. "/System/Volumes/Data"
            // still shows up under "/System/Volumes") — any real content it
            // has was, or will be, counted through whichever path actually
            // claims that volume.
            return DirectoryNode(path: path, name: name, kind: .directory, sizeBytes: 0)
        }

        guard depth < maxDepth else {
            let startDeviceID = deviceID(of: path)
            let size = quickRecursiveSize(of: path, startDeviceID: startDeviceID, fileManager: fileManager, isCancelled: isCancelled)
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
            if isCancelled() { break }
            if budget <= 0 {
                // Global budget exhausted. Rather than `break`-ing here (which
                // would silently drop this and every remaining sibling —
                // undercounting `path`'s total size, potentially drastically
                // once the root is an entire disk instead of one home
                // directory), fall back to `quickLeaf`, the same
                // budget-exempt total-size-only path already used once
                // `maxDepth` is reached. (This calls `quickLeaf` directly
                // rather than recursing into `node(at:...)` itself with a
                // forced `depth: maxDepth`, because `node`'s own first line
                // is `if isCancelled() || budget <= 0 { return nil }` — with
                // budget already at/below zero that guard would immediately
                // discard the call before it ever reached the quick-size
                // branch.) `path`'s reported size stays accurate; only the
                // depth of detail is reduced for whatever wasn't reached
                // before the budget ran out, and the user can still drill
                // into any such leaf to trigger a fresh, budget-refreshed
                // scan.
                if let quickChild = quickLeaf(
                    at: entry,
                    volumeGuard: volumeGuard,
                    fileManager: fileManager,
                    isCancelled: isCancelled
                ) {
                    children.append(quickChild)
                }
                continue
            }
            if let child = node(
                at: entry,
                depth: depth + 1,
                maxDepth: maxDepth,
                maxChildrenPerDirectory: maxChildrenPerDirectory,
                budget: &budget,
                fileManager: fileManager,
                isCancelled: isCancelled,
                volumeGuard: volumeGuard
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

    /// Cheap, budget-exempt fallback for a single directory entry once the
    /// global node budget has been exhausted mid-walk (see the loop in
    /// `node(at:...)` above). Deliberately does *not* recurse into
    /// `node(at:...)` itself — that function's own first line bails out
    /// immediately once `budget <= 0`, which is exactly the state we're in
    /// when this is called, so re-entering it would just discard the call.
    /// Instead this mirrors `node(at:...)`'s `depth >= maxDepth` branch
    /// directly: same vanished/symlink/mount-point handling, same
    /// `quickRecursiveSize` total, just never spends any node budget and
    /// never materializes children.
    private static func quickLeaf(
        at url: URL,
        volumeGuard: MountPointGuard,
        fileManager: FileManager,
        isCancelled: @Sendable () -> Bool
    ) -> DirectoryNode? {
        guard let resourceValues = try? url.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]
        ) else {
            return nil
        }
        if resourceValues.isSymbolicLink == true { return nil }

        let path = url.path
        let name = url.lastPathComponent

        guard resourceValues.isDirectory == true else {
            return DirectoryNode(path: path, name: name, kind: .file, sizeBytes: Int64(resourceValues.fileSize ?? 0))
        }

        guard volumeGuard.allowsDescending(into: path) else {
            return DirectoryNode(path: path, name: name, kind: .directory, sizeBytes: 0)
        }

        let startDeviceID = deviceID(of: path)
        let size = quickRecursiveSize(of: path, startDeviceID: startDeviceID, fileManager: fileManager, isCancelled: isCancelled)
        return DirectoryNode(path: path, name: name, kind: .directory, sizeBytes: size)
    }

    /// Fast recursive size-only sum (no per-entry node materialization, and
    /// deliberately exempt from `maxNodesBudget` — it never allocates a
    /// node per entry), used once `maxDepth` is reached so a directory's
    /// total is still accurate without spending the node budget
    /// subdividing further. Mirrors `DevToolsDetectors.DevToolsFS.recursiveSize`.
    ///
    /// `startDeviceID` — `path`'s own device id, computed once by the
    /// caller — bounds this sum to `path`'s own physical volume, the same
    /// way `MountPointGuard` bounds the main walk. `FileManager`'s
    /// enumerator does not stop at mount points on its own, so without this
    /// a directory that happens to contain some other, unrelated mounted
    /// volume deep inside it (e.g. a manually-mounted disk image, past
    /// `maxDepth` so it never went through the main per-directory guard)
    /// could otherwise get silently folded into this "quick" total. This
    /// helper only ever *excludes* extra volumes — it never re-includes the
    /// firmlinked Data volume the main walk may have already accounted for
    /// elsewhere, so it cannot itself cause double counting.
    private static func quickRecursiveSize(
        of path: String,
        startDeviceID: dev_t?,
        fileManager: FileManager,
        isCancelled: @Sendable () -> Bool
    ) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey],
            options: [],
            errorHandler: { _, _ in true }
        ) else { return 0 }

        var total: Int64 = 0
        var counter = 0
        for case let fileURL as URL in enumerator {
            counter += 1
            if counter.isMultiple(of: 256), isCancelled() { break }
            guard let values = try? fileURL.resourceValues(
                forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey]
            ) else { continue }
            if values.isSymbolicLink == true { continue }
            if values.isDirectory == true {
                if let startDeviceID, deviceID(of: fileURL.path) != startDeviceID {
                    // Crossed onto a different volume than `path` itself —
                    // don't descend into it from this cheap size-only pass.
                    enumerator.skipDescendants()
                }
                continue
            }
            if values.isRegularFile == true, let size = values.fileSize {
                total += Int64(size)
            }
        }
        return total
    }
}

// MARK: - Mount-point deduplication

/// `stat(2)`'s device id for `path` (via `lstat`, so a symlink is never
/// followed to reach it) — `nil` if `path` can't be stat'd at all (vanished,
/// unreadable, etc.), in which case callers treat that as "nothing special
/// here" and let the normal read/permission handling elsewhere report the
/// failure.
///
/// File-scope (not a member of `DirectorySizeTreeBuilder`) and `internal`
/// rather than `private` so `MountPointGuard` below can use it as a default
/// argument and so tests can call it directly against real paths without
/// needing to fabricate a second real mount point.
func deviceID(of path: String) -> dev_t? {
    var info = stat()
    guard lstat(path, &info) == 0 else { return nil }
    return info.st_dev
}

/// Identifies which APFS *container* (not volume — a container can hold
/// several volumes) `path` lives on, derived from the BSD device node
/// `statfs(2)` reports it as mounted from (`f_mntfromname`, e.g.
/// "/dev/disk3s5") by stripping everything after the leading "diskN"
/// component ("/dev/disk3s1s1" and "/dev/disk3s5" both reduce to "disk3").
///
/// This is deliberately device-id-agnostic and path-agnostic: it doesn't
/// hardcode "/System/Volumes/Data" (an implementation detail of exactly how
/// Apple currently wires up firmlinks, which could change) or assume any
/// particular slice-number scheme. It only relies on the stable, long-
/// standing APFS invariant that every volume belonging to one boot "volume
/// group" (the sealed system volume and its read-write Data volume) is a
/// slice of the *same* container disk, while an unrelated external drive or
/// network share is a slice of a *different* container (or has no BSD disk
/// node at all, e.g. `smbfs`/`nfs`, in which case this returns `nil` and
/// that volume is treated as foreign — see `MountPointGuard`).
///
/// Returns `nil` if `path` can't be `statfs`'d, or if `f_mntfromname`
/// doesn't look like a local BSD disk device (e.g. a network mount).
func containerIdentifier(of path: String) -> String? {
    var info = statfs()
    guard statfs(path, &info) == 0 else { return nil }
    let mountedFrom = withUnsafeBytes(of: info.f_mntfromname) { raw -> String in
        String(cString: raw.bindMemory(to: CChar.self).baseAddress!)
    }
    guard let diskName = mountedFrom.split(separator: "/").last,
          let match = diskName.range(of: #"^disk[0-9]+"#, options: .regularExpression) else {
        return nil
    }
    return String(diskName[match])
}

/// Coordinates which physical volumes a single ``DirectorySizeTreeBuilder``
/// walk has already decided to include, so a walk started at "/" doesn't
/// double-count — or, symmetrically, doesn't silently pull in — data
/// reachable through more than one filesystem path.
///
/// **Why this exists.** Since macOS Catalina, the boot volume macOS shows
/// as one seamless "/" is actually *two* separate APFS volumes in one
/// volume group: a sealed, read-only system volume mounted at "/", and a
/// read-write "Data" volume macOS mounts at "/System/Volumes/Data" and then
/// re-exposes at the *top level* of "/" — e.g. "/Users", "/Applications",
/// "/Library", "/Volumes", "/cores" — via firmlinks (directory-level
/// bind-mounts, distinct from symlinks: `isSymbolicLinkKey` reports `false`
/// for them, so the symlink guard elsewhere in this file does not catch
/// this case). A naive recursive walk from "/" would therefore reach the
/// exact same files twice: once via, say, "/Users/<you>/Documents", and
/// again via "/System/Volumes/Data/Users/<you>/Documents" — potentially
/// doubling (or worse — several top-level paths are firmlinked) the
/// reported size of the whole disk.
///
/// **The fix is device-id based, not path based**, so it keeps working
/// even if Apple changes exactly which top-level paths are firmlinked:
/// `deviceID(of:)` identifies which physical/logical volume a directory
/// actually lives on. Every directory on the *same* device as the scan
/// root is unambiguously normal — no special handling. The first time the
/// walk crosses onto a *different* device, this type checks (via
/// `containerIdentifier(of:)`) whether that device belongs to the same
/// APFS container as the root — i.e. whether it's the root's own paired
/// Data volume rather than some unrelated disk. If so, that one volume is
/// "claimed": it gets walked normally this one time, and its device id is
/// remembered so every *other* path that also leads there (including the
/// canonical "/System/Volumes/Data" itself, whichever order the walk
/// happens to encounter things in — directory enumeration order is not
/// guaranteed) is recognized as a duplicate and skipped. A device that does
/// *not* share the root's container — a genuinely separate external drive
/// or network share mounted somewhere under the tree, e.g. under
/// "/Volumes" — is rejected the first time it's seen, and that rejection is
/// cached too, so it's never walked and the check is never repeated for it.
///
/// Reference type (rather than threading a `Set` through every recursive
/// call via `inout`) purely for call-site brevity — every call happens
/// sequentially on whatever single thread runs one
/// `DirectorySizeTreeBuilder.build` walk (a detached `Task` in
/// `SpaceLensView`), so no synchronization is needed and this deliberately
/// is not `Sendable`.
final class MountPointGuard {
    private let deviceIDProvider: (String) -> dev_t?
    private let containerIDProvider: (String) -> String?
    private let rootDeviceID: dev_t?
    private let rootContainerID: String?
    private var decidedDeviceIDs: Set<dev_t>

    /// - Parameters:
    ///   - rootPath: The scan root's path — defines both "the volume every
    ///     other directory is compared against" and "the container that
    ///     defines which *other* volume, if any, is in scope."
    ///   - deviceIDProvider/containerIDProvider: Real filesystem lookups by
    ///     default; injectable so tests can exercise the claim/reject state
    ///     machine against synthetic device/container maps instead of
    ///     needing to fabricate a real second mount point.
    init(
        rootPath: String,
        deviceIDProvider: @escaping (String) -> dev_t? = deviceID(of:),
        containerIDProvider: @escaping (String) -> String? = containerIdentifier(of:)
    ) {
        self.deviceIDProvider = deviceIDProvider
        self.containerIDProvider = containerIDProvider
        self.rootDeviceID = deviceIDProvider(rootPath)
        self.rootContainerID = containerIDProvider(rootPath)
        self.decidedDeviceIDs = rootDeviceID.map { [$0] } ?? []
    }

    /// Whether `path` — a directory already confirmed by the caller to
    /// exist and not be a symlink — should be walked as a normal part of
    /// the tree, or treated as either a duplicate path onto already-
    /// accounted-for data or an out-of-scope foreign volume.
    func allowsDescending(into path: String) -> Bool {
        guard let deviceID = deviceIDProvider(path) else {
            // Couldn't stat it — not this type's problem to solve; let the
            // normal read/permission handling further up in `node(at:...)`
            // deal with whatever's wrong when it tries to actually read it.
            return true
        }
        if deviceID == rootDeviceID { return true }

        if decidedDeviceIDs.contains(deviceID) {
            // Either a volume we already claimed and fully walked via a
            // different path (double-count risk), or one we already
            // rejected as foreign (out-of-scope risk). Either way: no.
            return false
        }

        if let rootContainerID, containerIDProvider(path) == rootContainerID {
            // First time crossing onto this volume, and it shares the
            // root's APFS container — this is the boot volume's own
            // firmlinked Data volume. Claim it so every other path leading
            // here for the rest of this walk is recognized as a duplicate.
            decidedDeviceIDs.insert(deviceID)
            return true
        }

        // A genuinely different disk or network volume. Remember the
        // rejection so this container check isn't repeated for every path
        // underneath it.
        decidedDeviceIDs.insert(deviceID)
        return false
    }
}
