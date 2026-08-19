import Foundation

/// User-configured set of domains whose data the user wants preserved
/// ("whitelist per siti da preservare" — PROMPT MASTER §5.1).
///
/// ## What this can and cannot do — read before wiring this in anywhere
///
/// Browser cookie/history/cache stores are, for the most part, single
/// opaque files (SQLite databases, binary cookie jars) covering *every
/// site at once* — there is no row inside them this package will ever open
/// or touch (see each detector's doc comment for the full safety framing).
/// `SitePreserveList` can therefore only be honored at **file/directory
/// granularity**: a detector either
///
/// 1. finds a genuinely per-origin directory layout (some browsers do use
///    one for parts of their storage, e.g. IndexedDB) and excludes whole
///    directories whose origin matches an entry here, or
/// 2. finds only a monolithic store and cannot exclude anything — in which
///    case it must say so plainly in `ScanItem.reason` rather than silently
///    ignoring this list's intent.
///
/// See each detector's doc comment for which case applies to which store.
public struct SitePreserveList: Sendable, Hashable {
    /// Normalized domains (lowercased, no leading `www.` or `*.`) the user
    /// wants preserved.
    public let domains: Set<String>

    public init(domains: Set<String> = []) {
        self.domains = Set(domains.map(Self.normalize))
    }

    public var isEmpty: Bool { domains.isEmpty }

    /// True if `host` (or any of its parent domains) is on the preserve
    /// list — e.g. a list containing "example.com" also preserves
    /// "www.example.com" and "sub.example.com".
    public func preserves(host: String) -> Bool {
        guard !domains.isEmpty else { return false }
        let normalizedHost = Self.normalize(host)
        if domains.contains(normalizedHost) { return true }
        return domains.contains { normalizedHost.hasSuffix("." + $0) }
    }

    private static func normalize(_ raw: String) -> String {
        var s = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("*.") { s.removeFirst(2) }
        if s.hasPrefix("www.") { s.removeFirst(4) }
        return s
    }
}
