import Darwin
import Foundation
import Security
import SafetyRules

/// A validated, ready-to-shred request for exactly one file.
///
/// The only way to obtain a `ShredRequest` is `Shredder.requestShred(path:)`
/// succeeding — its initializer is `fileprivate` to this source file, so
/// nothing outside `Shredder.swift` (not even this package's own other
/// files, and not a `@testable import` from the test target, since
/// `fileprivate`/`private` access is scoped to the *file*, not lifted by
/// testability the way `internal` is) can fabricate one from a raw path
/// string. That is deliberate: it is the mechanism by which this package
/// makes "confirm-shred a path nobody validated" a compile error, not just a
/// runtime check — see `Shredder`'s doc comment for how this is meant to
/// compose with `MainAppUI`'s two-dialog confirmation flow.
///
/// Holding a `ShredRequest` for a while (e.g. across a "are you sure?" /
/// "are you REALLY sure?" dialog pair) is expected and fine — but the
/// filesystem can change underneath it in the meantime, so
/// `Shredder.confirmShred` re-validates everything independently rather
/// than trusting this value's contents blindly. Treat this type as a
/// *receipt describing what would happen*, not a capability that itself
/// guarantees the file is still safe to destroy by the time it's used.
public struct ShredRequest: Sendable, Equatable {
    /// Fully resolved, absolute path (tilde-expanded, standardized). This is
    /// the exact path `confirmShred` will open and overwrite.
    public let path: String

    /// Size in bytes at the moment of validation, used to size the
    /// overwrite passes. Re-read from disk (not trusted from here) at the
    /// start of `confirmShred` — see that method's doc comment.
    public let fileSizeBytes: Int64

    /// When `requestShred` produced this value — surfaced so a caller (or
    /// its UI) can decide a request that's been sitting around "too long"
    /// deserves a fresh `requestShred` rather than being confirmed as-is.
    /// `Shredder` itself does not enforce any expiry.
    public let requestedAt: Date

    fileprivate init(path: String, fileSizeBytes: Int64, requestedAt: Date) {
        self.path = path
        self.fileSizeBytes = fileSizeBytes
        self.requestedAt = requestedAt
    }
}

/// Secure, multi-pass, single-file deletion — PROMPT MASTER §5.1's
/// "cancellazione sicura file singoli (multi-pass opzionale)".
///
/// ## Why this bypasses quarantine, deliberately
///
/// Every other destructive path in this app goes through
/// `SafetyRules.FileSystemQuarantineManager`: nothing is instantly and
/// irreversibly gone, everything is reversible for a retention window. This
/// type is the **one deliberate exception**. A secure overwrite is only
/// meaningful if it is actually irreversible immediately — quarantining the
/// file first (moving it, still fully intact, into a quarantine folder)
/// would defeat the entire point. So `Shredder` never quarantines, and
/// never will.
///
/// Because of that, this type carries safety obligations the quarantine
/// flow gets structurally for free:
///
/// 1. **Never wired into the scan pipeline.** This package has no
///    dependency on `CoreScanEngine` (see `Package.swift`) and defines no
///    `Detector`. A scan verdict (`safeAuto` / `needsConfirmation`) must
///    never feed a path into this type automatically — only an explicit,
///    deliberate user action on a specific file they chose.
/// 2. **Two-step API, by construction, not just by convention.**
///    `requestShred(path:)` validates a path and returns a `ShredRequest`
///    describing what *would* happen — it never touches the file's
///    content. `confirmShred(_:passes:)` is the only method that ever opens
///    a file for writing, and it only accepts a `ShredRequest` — there is
///    no overload that takes a raw path string, so a caller cannot skip
///    straight from "path" to "destroyed". `MainAppUI` is expected to put
///    one confirmation dialog between step 1 and step 2 (arguably two,
///    since the spec calls this out as needing to feel graver than a normal
///    delete) — this type only guarantees the *shape*, not the UI.
/// 3. **Denylist-gated at both steps.** `requestShred` refuses any path
///    matched by `SafetyRules.Denylist.forbiddenReason` or
///    `isLikelyBootVolumeRoot`, exactly like `FileSystemQuarantineManager`
///    does. `confirmShred` re-runs the identical check on the resolved path
///    before touching disk — defense in depth, in case the `ShredRequest`
///    was held for a while and something changed (a symlink swap, a
///    different file now living at that path, etc.). There is no override
///    and no "advanced mode" that skips this for either method.
///
/// ## Honest limits — read this before trusting "shredded" to mean "gone"
///
/// Multi-pass overwrite-then-delete is a **reasonable-effort** security
/// measure, not a cryptographic guarantee — especially on the SSD/APFS
/// setup every supported Mac uses:
///
/// - **Wear leveling & TRIM.** An SSD's flash translation layer decides
///   which physical NAND cells a logical write actually lands on, and
///   routinely does *not* reuse the same cells a previous write to the same
///   logical offset used. Overwriting a file's logical bytes N times is not
///   the same as overwriting the physical cells that held the *original*
///   data — those may already be sitting untouched (or TRIM'd, or
///   remapped) elsewhere on the die, potentially recoverable with
///   specialized tools.
/// - **APFS copy-on-write.** If the file was ever cloned (`cp -c`, a Finder
///   duplicate, an app that clones instead of copies) or is a Time Machine
///   local-snapshot source, a normal in-place `write()` to it triggers
///   copy-on-write: the write lands on freshly allocated blocks, and the
///   blocks the clone/snapshot still references — which may hold the
///   original content — are untouched by this overwrite entirely. This
///   type has no way to detect or defeat that from user space.
/// - **Hard links.** If another directory entry hard-links the same inode
///   (rare, but possible on APFS), the overwrite passes affect the shared
///   data — so the *other* name now also points at destroyed content — but
///   `confirmShred` only removes the one directory entry it was given via
///   `unlink`; the other name keeps existing, now pointing at zeroed/
///   randomized/truncated data rather than the original.
///
/// None of this is a reason not to offer the feature — multi-pass overwrite
/// is still meaningfully more effort to recover from than a plain delete,
/// and is the honest, standard state of the art for user-space secure
/// deletion on modern hardware. It is a reason not to *oversell* it: the UI
/// copy this type's consumers write should say something like "makes
/// recovery significantly harder", never "guarantees the data is
/// unrecoverable" — full-disk encryption (already standard via FileVault)
/// is what actually makes a single file's residual traces unrecoverable at
/// rest, and destroying the file's encryption-relevant key material (not
/// something this type does) is the more reliable primitive on SSDs in
/// general. See `SAFETY_RULES.md` / `ARCHITECTURE.md` for where this should
/// be reflected at the product-doc level (flagged, not written, by this
/// package's change — see the implementing agent's final report).
///
/// ## Overwrite scheme
///
/// Each pass writes the file's full length, in this order (indices past 2
/// repeat the last pattern):
/// 1. all zero bytes (`0x00`)
/// 2. all one bytes (`0xFF`)
/// 3.+ cryptographically random bytes (`SecRandomCopyBytes`), regenerated
///    per chunk rather than a single repeated buffer
///
/// This is the classic "zero / ones / random" scheme rather than
/// all-random-every-pass — the fixed first two patterns make it trivial to
/// verify a pass actually happened by inspecting file content (which this
/// package's own tests do), while the trailing random pass(es) still deny
/// simple pattern-matching recovery. After every pass, the written data is
/// flushed with `fcntl(F_FULLFSYNC)` (falling back to `fsync` if
/// unavailable on the underlying filesystem) before the next pass or the
/// final truncate begins.
///
/// `passes` defaults to 3. A caller may request 1 (fast, still a real
/// overwrite) up to as many as they like; `0` or negative is rejected
/// before any I/O.
///
/// ## Cancellation
///
/// `confirmShred` checks `Task` cancellation between every pass, and
/// additionally at chunk granularity *within* a single pass on a large
/// file, so an in-progress shred of a huge file is not unabortable. If
/// cancelled:
///
/// - The file is **never left partially truncated or partially deleted** —
///   truncate-to-zero and the final `unlink` only happen after every
///   requested pass has completed and been fsync'd. A cancelled shred
///   always leaves a complete, still-present file at its original length.
/// - Whatever whole passes had already completed before cancellation was
///   observed remain applied — they are not, and cannot be, rolled back.
///   In particular: if even the *first* pass (all-zero) completed before
///   cancellation landed, the original content is already fully
///   overwritten and gone, even though the file itself is still there. If
///   cancellation lands *during* the first pass, part of the file may still
///   hold original content and part may already be zeroed.
/// - `confirmShred` throws `ShredError.cancelled(path:passesCompleted:totalPasses:)`
///   rather than a bare `CancellationError`, so a caller can tell exactly
///   how far it got. The same `ShredRequest` can be passed to a fresh
///   `confirmShred` call to resume — the file's size hasn't changed, so
///   the request is still valid (re-validated independently anyway).
public actor Shredder {
    private let fileManager: FileManager

    /// - Parameter fileManager: injectable for tests; defaults to `.default`.
    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    // MARK: - Step 1: validate only, never touches file content

    /// Resolves and validates `path`, refusing anything forbidden, missing,
    /// a directory, or a symbolic link. Does not open, read, or write the
    /// file's content — the only thing this does with the filesystem is
    /// `stat`-shaped existence/metadata checks.
    public func requestShred(path: String) throws -> ShredRequest {
        let resolved = Self.resolve(path: path)
        let size = try Self.validate(path: resolved, fileManager: fileManager)
        return ShredRequest(path: resolved, fileSizeBytes: size, requestedAt: Date())
    }

    // MARK: - Step 2: the only method that ever touches disk

    /// Overwrites `request`'s file for `passes` passes, then truncates it to
    /// zero length and removes its directory entry. This is the **only**
    /// method in this package that opens a file for writing or deletes
    /// anything — see this type's doc comment for the full scheme,
    /// cancellation behavior, and honest limits.
    ///
    /// - Parameter onPassCompleted: optional progress callback, invoked
    ///   synchronously after each pass finishes (and is fsync'd), with
    ///   `(passesCompletedSoFar, totalPasses)`. Intended for a UI progress
    ///   indicator during the (potentially slow) confirmation step; also
    ///   doubles as this package's own test seam for observing
    ///   intermediate, overwritten-but-not-yet-deleted file state.
    public func confirmShred(
        _ request: ShredRequest,
        passes: Int = 3,
        onPassCompleted: (@Sendable (_ passesCompletedSoFar: Int, _ totalPasses: Int) -> Void)? = nil
    ) async throws {
        guard passes >= 1 else { throw ShredError.invalidPassCount(passes) }

        // Defense in depth: re-validate independently of whatever
        // `requestShred` found, in case `request` is stale (held across a
        // confirmation dialog while something on disk changed). This
        // re-reads the current size from disk rather than trusting
        // `request.fileSizeBytes`.
        let currentSize = try Self.validate(path: request.path, fileManager: fileManager)

        // `O_NOFOLLOW` closes the TOCTOU window between `validate`'s
        // lstat-shaped symlink check above and this `open()` call: without
        // it, something else running as the same user could swap the leaf
        // for a symlink in between, and `open(O_WRONLY)` would silently
        // follow it — overwriting whatever the symlink points at instead of
        // refusing, exactly the failure mode `ShredError.isSymbolicLink` is
        // meant to prevent. With `O_NOFOLLOW`, that race now fails the
        // `open()` call itself (`errno == ELOOP`) instead of succeeding.
        let fd = request.path.withCString { open($0, O_WRONLY | O_NOFOLLOW) }
        guard fd >= 0 else {
            if errno == ELOOP {
                throw ShredError.isSymbolicLink(request.path)
            }
            throw ShredError.underlying("Unable to open \"\(request.path)\" for writing (errno \(errno)).")
        }
        defer { close(fd) }

        var passesCompleted = 0
        do {
            if currentSize > 0 {
                for passIndex in 0..<passes {
                    try Task.checkCancellation()
                    let pattern = Self.pattern(forPassIndex: passIndex)
                    try await Self.performPass(fd: fd, totalSize: currentSize, pattern: pattern, passIndex: passIndex)
                    passesCompleted += 1
                    onPassCompleted?(passesCompleted, passes)
                }
            } else {
                // Nothing to overwrite in a zero-length file; still counts
                // as every pass "completed" for reporting purposes.
                passesCompleted = passes
                onPassCompleted?(passesCompleted, passes)
            }
        } catch is CancellationError {
            throw ShredError.cancelled(path: request.path, passesCompleted: passesCompleted, totalPasses: passes)
        }

        // Truncate to zero length before unlinking: on filesystems where
        // this matters, it drops the old extent mapping in addition to the
        // pass overwrite itself. This only runs once every requested pass
        // has completed — see the cancellation note above.
        guard ftruncate(fd, 0) == 0 else {
            throw ShredError.underlying("Failed to truncate \"\(request.path)\" after overwrite (errno \(errno)).")
        }

        do {
            try fileManager.removeItem(atPath: request.path)
        } catch {
            // The data is already destroyed (every pass ran, file is
            // zero-length) — only the directory entry itself failed to
            // remove. Surface this distinctly rather than implying the
            // overwrite failed.
            throw ShredError.underlying(
                "Overwrite completed and the file was truncated to zero length, but removing its " +
                "directory entry at \(request.path) failed: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Shared validation (used by both steps)

    /// Path prefix/pattern/git checks plus existence/type checks. Shared so
    /// `confirmShred` re-runs *exactly* what `requestShred` ran, rather than
    /// a hand-maintained duplicate that could drift out of sync.
    @discardableResult
    private static func validate(path: String, fileManager: FileManager) throws -> Int64 {
        if let reason = Denylist.forbiddenReason(forPath: path) {
            throw ShredError.pathForbidden(reason)
        }
        if Denylist.isLikelyBootVolumeRoot(path) {
            throw ShredError.pathForbidden("Path is a volume root: \(path)")
        }

        // Checked before `fileExists` so a broken/dangling symlink is still
        // reported as `.isSymbolicLink` rather than `.sourceNotFound` — the
        // caller picked a symlink either way, which is the thing we're
        // refusing. `destinationOfSymbolicLink` only inspects the leaf
        // component (lstat-shaped, does not follow), so an ordinary path
        // that merely traverses a symlinked *ancestor* directory (e.g.
        // `/tmp` -> `/private/tmp` on every Mac) is unaffected.
        if (try? fileManager.destinationOfSymbolicLink(atPath: path)) != nil {
            throw ShredError.isSymbolicLink(path)
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
            throw ShredError.sourceNotFound(path)
        }
        if isDirectory.boolValue {
            throw ShredError.isDirectory(path)
        }

        let attributes = try fileManager.attributesOfItem(atPath: path)
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }

    /// Expands `~` and standardizes the path (removes redundant `.`/`..`/
    /// duplicate separators). Deliberately does **not** fully resolve
    /// symlinks — see `validate`'s doc comment for why the leaf component's
    /// symlink-ness needs to still be visible afterward.
    private static func resolve(path: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        if (expanded as NSString).isAbsolutePath {
            return (expanded as NSString).standardizingPath
        }
        // Callers are expected to pass absolute paths (every other safety
        // check in this app assumes that too), but resolve relative to the
        // current directory rather than silently misbehaving if one slips
        // through.
        let absolute = (FileManager.default.currentDirectoryPath as NSString).appendingPathComponent(expanded)
        return (absolute as NSString).standardizingPath
    }

    // MARK: - Overwrite pass implementation

    private enum OverwritePattern: Sendable {
        case zeros
        case ones
        case random
    }

    /// Zero-based pass index -> pattern. See this type's "Overwrite scheme"
    /// doc comment for the rationale.
    private static func pattern(forPassIndex index: Int) -> OverwritePattern {
        switch index {
        case 0: .zeros
        case 1: .ones
        default: .random
        }
    }

    private static let chunkSizeBytes = 4 * 1024 * 1024 // 4 MiB

    /// Overwrites `fd`'s full `totalSize` bytes with `pattern`, in
    /// `chunkSizeBytes`-sized writes from offset 0, then flushes to durable
    /// storage. Checks cancellation at the start of every chunk (not just
    /// between whole passes) so a single pass over a very large file stays
    /// abortable within a few chunks' worth of I/O, not just at pass
    /// boundaries.
    private static func performPass(
        fd: Int32,
        totalSize: Int64,
        pattern: OverwritePattern,
        passIndex: Int
    ) async throws {
        guard lseek(fd, 0, SEEK_SET) == 0 else {
            throw ShredError.underlying("Failed to seek to start of file for pass \(passIndex + 1) (errno \(errno)).")
        }

        let fixedBuffer: [UInt8]?
        switch pattern {
        case .zeros: fixedBuffer = [UInt8](repeating: 0x00, count: min(chunkSizeBytes, Int(totalSize)))
        case .ones: fixedBuffer = [UInt8](repeating: 0xFF, count: min(chunkSizeBytes, Int(totalSize)))
        case .random: fixedBuffer = nil
        }

        var remaining = totalSize
        while remaining > 0 {
            try Task.checkCancellation()

            let thisChunkSize = Int(min(Int64(chunkSizeBytes), remaining))
            var chunk: [UInt8]
            if let fixedBuffer {
                chunk = thisChunkSize == fixedBuffer.count ? fixedBuffer : Array(fixedBuffer.prefix(thisChunkSize))
            } else {
                chunk = [UInt8](repeating: 0, count: thisChunkSize)
                let status = chunk.withUnsafeMutableBytes { rawBuffer in
                    SecRandomCopyBytes(kSecRandomDefault, thisChunkSize, rawBuffer.baseAddress!)
                }
                guard status == errSecSuccess else {
                    throw ShredError.underlying("Failed to generate random bytes for pass \(passIndex + 1) (status \(status)).")
                }
            }

            let written = chunk.withUnsafeBytes { rawBuffer in
                write(fd, rawBuffer.baseAddress, thisChunkSize)
            }
            guard written == thisChunkSize else {
                throw ShredError.underlying(
                    "Short write during pass \(passIndex + 1): wrote \(written)/\(thisChunkSize) bytes (errno \(errno))."
                )
            }

            remaining -= Int64(thisChunkSize)
            await Task.yield()
        }

        // `F_FULLFSYNC` asks the drive to flush to durable storage, not just
        // to its write cache the way plain `fsync` does — meaningful for a
        // "secure" overwrite. Not every filesystem/mount supports it, so
        // fall back to `fsync` rather than failing the whole pass.
        if fcntl(fd, F_FULLFSYNC) != 0 {
            guard fsync(fd) == 0 else {
                throw ShredError.underlying("fsync failed after pass \(passIndex + 1) (errno \(errno)).")
            }
        }
    }
}
