import Foundation

/// Shared reason-text builders so every detector states the same safety
/// framing consistently instead of each hand-rolling similar prose.
enum ReasonText {
    /// Reason text for a store that is a **single opaque file/directory
    /// covering every site at once** (a cookie jar, a history database, a
    /// hashed-filename cache) — `SitePreserveList` cannot exclude anything
    /// inside it, so that must be said plainly rather than silently ignored.
    static func monolithicStore(
        description: String,
        preserveList: SitePreserveList,
        runningWarning: String?
    ) -> String {
        var parts = [description]
        if !preserveList.isEmpty {
            let count = preserveList.domains.count
            let entryWord = count == 1 ? "entry" : "entries"
            parts.append(
                "Your site preserve list has \(count) \(entryWord) that cannot be honored here: this is a single store covering every site at once, not one file per site, so cleaning it would remove data for preserved sites along with everything else."
            )
        }
        if let runningWarning {
            parts.append(runningWarning)
        }
        return parts.joined(separator: " ")
    }

    /// Warning fragment appended to `reason` when the owning browser process
    /// currently appears to be running.
    static func runningWarning(browserName: String) -> String {
        "\(browserName) is currently running — quarantining this file while the browser has it open may cause unexpected behavior (e.g. the browser recreating it, or a write conflict)."
    }
}
