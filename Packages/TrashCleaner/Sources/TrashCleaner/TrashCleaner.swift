import CoreScanEngine

/// Convenience registry so the app layer can register every Trash Bins
/// detector with a `ScanEngine` in one call:
///
/// ```swift
/// let engine = ScanEngine()
/// await engine.register(TrashCleanerRegistry.all())
/// ```
///
/// Covers Finder's Trash (boot volume `~/.Trash` plus every mounted
/// external volume's `.Trashes/<uid>`), Mail.app's local trash mailboxes,
/// and Photos' "Recently Deleted" — per PROMPT MASTER §5.1. See
/// `CoreScanEngine.Detector` for the interface every detector below
/// implements, and each individual `*Detector.swift` file for its specific
/// coverage and (for Mail/Photos) documented limitations.
///
/// ## Browser trash — deliberately not implemented
///
/// Safari, Chrome, and Firefox do not have a filesystem-visible "trash bin"
/// analogous to Finder's: a deleted download or history entry isn't staged
/// anywhere retrievable on disk the way Finder or Mail stage deleted items
/// — it's just gone, or (for history) tombstoned inside an opaque SQLite
/// database with no safe, well-defined "restore point" to surface as scan
/// results. Rather than invent something that isn't really "trash" to fill
/// out this category, `TrashCleaner` intentionally has no browser detector.
/// This is also *not* the place for browser cookies/history/cache in
/// general — those belong to Privacy Cleaner / System Junk, a different,
/// out-of-scope feature area that must not be touched from here. Revisit
/// only if a specific, well-defined, genuinely-retrievable "deleted items"
/// store is identified for a given browser.
public enum TrashCleanerRegistry {
    public static func all() -> [Detector] {
        [
            FinderTrashDetector(),
            MailTrashDetector(),
            PhotosRecentlyDeletedDetector()
        ]
    }
}
