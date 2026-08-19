import Foundation

/// Errors thrown by `Shredder`. Deliberately one case per distinct rejection
/// reason (rather than one generic "can't shred that" case) so a caller —
/// ultimately `MainAppUI`'s confirmation UI — can show the user *why*, and so
/// tests can assert on the specific reason rather than "it threw something".
public enum ShredError: Error, Sendable, Equatable, CustomStringConvertible {
    /// Defense in depth: `SafetyRules.Denylist.forbiddenReason` or
    /// `isLikelyBootVolumeRoot` matched. Thrown by both `requestShred`
    /// (first line of defense) and `confirmShred` (independent re-check —
    /// see `Shredder`'s doc comment for why a stale `ShredRequest` can't
    /// skip this). There is no override, no "advanced mode" — this case
    /// can never be caught and bypassed by design; if it's thrown, the path
    /// is not shreddable, full stop.
    case pathForbidden(String)

    /// Nothing exists at the resolved path.
    case sourceNotFound(String)

    /// The resolved path is a directory. `Shredder` only shreds single
    /// files ("cancellazione sicura file singoli" per PROMPT MASTER §5.1) —
    /// see `Shredder`'s doc comment for why this wasn't extended to
    /// directories.
    case isDirectory(String)

    /// The resolved path is itself a symbolic link. Refused rather than
    /// followed: opening a symlink for writing follows it to its target,
    /// so silently "shredding" a symlink would destroy whatever file it
    /// happens to point at — which may be far from what the user selected,
    /// possibly shared with other names via other links or clones. The
    /// caller must resolve the intended real file itself and pass that
    /// path explicitly.
    case isSymbolicLink(String)

    /// `confirmShred(passes:)` was called with a non-positive pass count.
    /// Thrown before any disk I/O happens.
    case invalidPassCount(Int)

    /// The operation was cooperatively cancelled (`Task` cancellation)
    /// partway through. `passesCompleted` full overwrite passes had already
    /// finished and been fsync'd before cancellation was observed; the file
    /// was **not** truncated or deleted. See `Shredder.confirmShred`'s doc
    /// comment for exactly what state the file is left in.
    case cancelled(path: String, passesCompleted: Int, totalPasses: Int)

    /// Any other I/O failure (open/write/fsync/truncate/unlink), including
    /// the case where overwrite + truncate fully succeeded but the final
    /// directory-entry removal failed — see the case's message for which.
    case underlying(String)

    public var description: String {
        switch self {
        case .pathForbidden(let reason):
            "Path is forbidden and cannot be shredded: \(reason)"
        case .sourceNotFound(let path):
            "No file exists at path: \(path)"
        case .isDirectory(let path):
            "Path is a directory, not a single file — Shredder only shreds single files: \(path)"
        case .isSymbolicLink(let path):
            "Path is a symbolic link — refused rather than followed to its target: \(path)"
        case .invalidPassCount(let passes):
            "Invalid pass count \(passes) — must be at least 1"
        case .cancelled(let path, let passesCompleted, let totalPasses):
            "Shred of \(path) cancelled after \(passesCompleted)/\(totalPasses) overwrite pass(es) — " +
            "file still exists, not deleted, but content from the completed pass(es) is already destroyed."
        case .underlying(let message):
            message
        }
    }
}
