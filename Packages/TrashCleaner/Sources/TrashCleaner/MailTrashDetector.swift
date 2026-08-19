import Foundation
import CoreScanEngine

/// Best-effort scan for local Mail.app trash mailboxes under
/// `~/Library/Mail` — covers "On My Mac" local account trash, plus whatever
/// locally-cached trash content exists for IMAP/Exchange accounts.
///
/// ## Known limitations — read before trusting this detector
///
/// Mail.app's on-disk mailbox layout under `~/Library/Mail/V<N>/...` is an
/// **undocumented implementation detail** that has changed across macOS
/// releases (the `V<N>` version number itself, per-account UUID directory
/// names, and the internal contents of a `.mbox` package are all
/// unpublished). There is no public API to ask "give me this account's
/// trash mailbox."
///
/// To stay honest about that, this detector does a **name-pattern** search:
/// it walks `~/Library/Mail` looking for `.mbox` packages whose name
/// contains "Trash" or "Deleted Messages" (case-insensitive) and reports
/// each *matched `.mbox` package as a whole* as a single `ScanItem` — it
/// does not attempt to parse or enumerate individual messages inside,
/// since the message-file layout inside a `.mbox` is even less stable than
/// the mailbox naming itself.
///
/// For IMAP/Exchange accounts, messages inside `<Account>/Trash.mbox` are a
/// **local cache** of what's already on the mail server — removing the
/// local copy doesn't touch the server, and Mail will re-download/re-sync
/// it. Only "On My Mac" local-account trash is genuinely local-only data
/// that won't come back on its own.
///
/// If `~/Library/Mail` doesn't exist, or nothing matches a recognizable
/// trash-mailbox name pattern, this returns **no items** — it never guesses
/// at an internal layout it can't verify.
///
/// Strictly read-only. See `CoreScanEngine.Detector`.
public struct MailTrashDetector: Detector {
    public let id = "trash.mail"
    public let displayName = "Mail Trash"
    public let category: DetectorCategory = .trash

    public init() {}

    public func scan(context: ScanContext) async throws -> [ScanItem] {
        var items: [ScanItem] = []

        for home in HomeDirectories.resolve(context) {
            if Task.isCancelled { break }
            let mailRoot = home + "/Library/Mail"
            guard TrashFS.isDirectory(mailRoot) else { continue }

            let matches = TrashFS.findDirectories(
                under: mailRoot,
                maxDepth: 6,
                isCancelled: { Task.isCancelled },
                matching: { name, _ in
                    guard name.hasSuffix(".mbox") else { return false }
                    let lowered = name.lowercased()
                    return lowered.contains("trash") || lowered.contains("deleted messages")
                }
            )

            for path in matches {
                if Task.isCancelled { break }
                let name = (path as NSString).lastPathComponent
                items.append(ScanItem(
                    path: path,
                    sizeBytes: TrashFS.recursiveSize(of: path, isCancelled: { Task.isCancelled }),
                    sourceDetectorID: "trash.mail.mbox",
                    category: "Mail — trash mailbox",
                    lastUsed: TrashFS.modificationDate(path).map { LastUsedEvidence(date: $0, source: .filesystemMTime) },
                    reason: "Mail.app trash mailbox '\(name)', matched by name under ~/Library/Mail. See MailTrashDetector's doc comment: this is a best-effort name match, not a parsed account structure, and IMAP trash here is only a local cache of server content."
                ))
            }
        }
        return items
    }
}
