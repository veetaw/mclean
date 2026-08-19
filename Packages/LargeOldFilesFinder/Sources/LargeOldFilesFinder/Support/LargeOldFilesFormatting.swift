import Foundation

/// Human-readable formatting for `ScanItem.reason` strings, e.g.
/// `"2.1 GB, last modified 14 months ago"`.
enum LargeOldFilesFormatting {

    /// A fresh `ByteCountFormatter` per call rather than a shared `static
    /// let` — `ByteCountFormatter` is a non-`Sendable` class, and this
    /// package follows the repo-wide convention (see `DevToolsFS`) of never
    /// storing non-`Sendable` Foundation objects as shared state.
    static func size(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    /// Renders an age in whole days as `"212 days"` below ~2 months, or a
    /// rounded `"~7 months"` above that — matching how people naturally
    /// describe file age, without pulling in `DateComponentsFormatter`
    /// calendar-arithmetic edge cases for what is ultimately a rough,
    /// human-facing figure.
    static func age(days: Int) -> String {
        guard days >= 60 else {
            return days == 1 ? "1 day" : "\(days) days"
        }
        let months = Int((Double(days) / 30.44).rounded())
        return months == 1 ? "~1 month" : "~\(months) months"
    }
}
