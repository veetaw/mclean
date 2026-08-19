import Foundation
import CoreScanEngine

/// Chrome cache/cookie/history/IndexedDB scan, across every profile
/// (`Default` and any `Profile *` directories) under
/// `~/Library/Application Support/Google/Chrome`.
///
/// ## Known limitations — read before trusting this detector
///
/// Per profile, three stores are reported as **whole, monolithic items**
/// because Chrome does not lay them out per-site on disk:
///
/// - `<profile>/Cache` — Chrome's "Simple Cache" backend: content-addressed
///   files named by a hash of the cache key, not by site. There is no
///   documented, stable way to map an entry back to a hostname without
///   parsing Chromium's private cache index format, which this detector
///   does not do.
/// - `<profile>/Cookies` — a single SQLite database holding cookies for
///   every site.
/// - `<profile>/History` — a single SQLite database holding browsing
///   history for every site.
///
/// `SitePreserveList` cannot be honored at file granularity for any of the
/// three above; each item's `reason` says so plainly instead of silently
/// ignoring the preserve list.
///
/// One store *does* give genuine per-site granularity: `<profile>/IndexedDB`
/// contains one subdirectory per origin, named like
/// `https_example.com_0.indexeddb.leveldb` (plus a matching `.blob`
/// sibling for large values). This naming scheme is a long-standing,
/// widely-observed Chromium implementation detail, not a documented public
/// format, so parsing it (`parseIndexedDBOrigin`) is inherently best-effort:
/// a directory name that doesn't match the expected shape is reported
/// as-is, unfiltered, rather than guessed at. Where it does parse, this
/// detector genuinely excludes preserved sites' IndexedDB directories from
/// the results.
///
/// This detector never opens or parses the contents of any cache/cookie/
/// history/IndexedDB file — only size, path, and modification time.
///
/// Strictly read-only. See `CoreScanEngine.Detector`.
public struct ChromePrivacyDetector: Detector {
    public let id = "privacy.chrome"
    public let displayName = "Chrome — cache, cookies, history & site storage"
    public let category: DetectorCategory = .privacy

    private let preserveList: SitePreserveList
    private let runningCheck: RunningBrowserCheck

    public init(
        preserveList: SitePreserveList = SitePreserveList(),
        runningCheck: RunningBrowserCheck = RunningBrowserCheck()
    ) {
        self.preserveList = preserveList
        self.runningCheck = runningCheck
    }

    public func scan(context: ScanContext) async throws -> [ScanItem] {
        let isRunning = await runningCheck.isRunning(bundleIdentifier: BrowserBundleID.chrome)
        let runningWarning = isRunning ? ReasonText.runningWarning(browserName: "Chrome") : nil

        var items: [ScanItem] = []
        for home in HomeDirectories.resolve(context) {
            if Task.isCancelled { break }
            let chromeRoot = home + "/Library/Application Support/Google/Chrome"
            guard PrivacyFS.isDirectory(chromeRoot) else { continue }

            let profiles = PrivacyFS.directoryEntries(chromeRoot).filter {
                $0 == "Default" || $0.hasPrefix("Profile ")
            }

            for profile in profiles {
                if Task.isCancelled { break }
                let profilePath = chromeRoot + "/" + profile
                guard PrivacyFS.isDirectory(profilePath) else { continue }
                items.append(contentsOf: scanMonolithicStores(profile: profile, profilePath: profilePath, runningWarning: runningWarning))
                items.append(contentsOf: scanIndexedDB(profile: profile, profilePath: profilePath, runningWarning: runningWarning))
            }
        }
        return items
    }

    private func scanMonolithicStores(profile: String, profilePath: String, runningWarning: String?) -> [ScanItem] {
        var items: [ScanItem] = []

        let cachePath = profilePath + "/Cache"
        if PrivacyFS.isDirectory(cachePath) {
            items.append(ScanItem(
                path: cachePath,
                sizeBytes: PrivacyFS.recursiveSize(of: cachePath, isCancelled: { Task.isCancelled }),
                sourceDetectorID: "privacy.chrome.cache",
                category: "Chrome — cache",
                lastUsed: PrivacyFS.modificationDate(cachePath).map { LastUsedEvidence(date: $0, source: .filesystemMTime) },
                reason: ReasonText.monolithicStore(
                    description: "Chrome's disk cache for profile '\(profile)' (content-addressed, not organized per-site). Chrome rebuilds this automatically as you browse.",
                    preserveList: preserveList,
                    runningWarning: runningWarning
                )
            ))
        }

        let cookiesPath = profilePath + "/Cookies"
        if PrivacyFS.exists(cookiesPath), let size = PrivacyFS.fileSize(cookiesPath) {
            items.append(ScanItem(
                path: cookiesPath,
                sizeBytes: size,
                sourceDetectorID: "privacy.chrome.cookies",
                category: "Chrome — cookies",
                lastUsed: PrivacyFS.modificationDate(cookiesPath).map { LastUsedEvidence(date: $0, source: .filesystemMTime) },
                reason: ReasonText.monolithicStore(
                    description: "Chrome's cookie database for profile '\(profile)'. This will sign you out of every site, not just tracking cookies.",
                    preserveList: preserveList,
                    runningWarning: runningWarning
                )
            ))
        }

        let historyPath = profilePath + "/History"
        if PrivacyFS.exists(historyPath), let size = PrivacyFS.fileSize(historyPath) {
            items.append(ScanItem(
                path: historyPath,
                sizeBytes: size,
                sourceDetectorID: "privacy.chrome.history",
                category: "Chrome — history",
                lastUsed: PrivacyFS.modificationDate(historyPath).map { LastUsedEvidence(date: $0, source: .filesystemMTime) },
                reason: ReasonText.monolithicStore(
                    description: "Chrome's browsing history database for profile '\(profile)'.",
                    preserveList: preserveList,
                    runningWarning: runningWarning
                )
            ))
        }

        return items
    }

    private func scanIndexedDB(profile: String, profilePath: String, runningWarning: String?) -> [ScanItem] {
        let indexedDBRoot = profilePath + "/IndexedDB"
        guard PrivacyFS.isDirectory(indexedDBRoot) else { return [] }

        var items: [ScanItem] = []
        for entry in PrivacyFS.directoryEntries(indexedDBRoot) {
            if Task.isCancelled { break }
            let path = indexedDBRoot + "/" + entry
            guard PrivacyFS.isDirectory(path) else { continue }

            let host = Self.parseIndexedDBOrigin(entry)
            if let host, preserveList.preserves(host: host) { continue }

            var reason = host != nil
                ? "IndexedDB storage for '\(host!)' in Chrome profile '\(profile)'. Site-specific: clearing this only affects that site's locally stored app data (it will re-sync/re-download from the site as needed)."
                : "IndexedDB storage directory '\(entry)' in Chrome profile '\(profile)'. Its name didn't match Chrome's usual '<scheme>_<host>_<port>.indexeddb.leveldb' naming pattern, so this detector could not determine which site it belongs to and cannot check it against your site preserve list."
            if let runningWarning {
                reason += " " + runningWarning
            }

            items.append(ScanItem(
                path: path,
                sizeBytes: PrivacyFS.recursiveSize(of: path, isCancelled: { Task.isCancelled }),
                sourceDetectorID: "privacy.chrome.indexeddb",
                category: "Chrome — site storage (IndexedDB)",
                lastUsed: PrivacyFS.modificationDate(path).map { LastUsedEvidence(date: $0, source: .filesystemMTime) },
                reason: reason
            ))
        }
        return items
    }

    /// Best-effort parse of a Chrome IndexedDB leaf directory name (e.g.
    /// `https_example.com_0.indexeddb.leveldb` or the matching `.blob`
    /// sibling) into its origin hostname. Returns `nil` if the name doesn't
    /// match the expected shape rather than guessing — this is an
    /// undocumented Chromium implementation detail, not a public format.
    static func parseIndexedDBOrigin(_ dirName: String) -> String? {
        let suffixes = [".indexeddb.leveldb", ".indexeddb.blob"]
        guard let suffix = suffixes.first(where: { dirName.hasSuffix($0) }) else { return nil }
        let base = String(dirName.dropLast(suffix.count))
        let parts = base.split(separator: "_")
        guard parts.count >= 3 else { return nil }
        let hostParts = parts.dropFirst().dropLast()
        guard !hostParts.isEmpty else { return nil }
        return hostParts.joined(separator: "_")
    }
}
