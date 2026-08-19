import Foundation
import CoreScanEngine

/// Firefox cache/cookie/history/per-origin-storage scan, across every
/// profile directory matching `*.default*` (e.g. `abcd1234.default`,
/// `abcd1234.default-release`) under
/// `~/Library/Application Support/Firefox/Profiles`.
///
/// ## Known limitations — read before trusting this detector
///
/// Per profile, three stores are reported as **whole, monolithic items**
/// because Firefox does not lay them out per-site on disk:
///
/// - `<profile>/cache2` — Firefox's disk cache, keyed by a hash of the
///   cache entry, not by site.
/// - `<profile>/cookies.sqlite` — a single SQLite database holding cookies
///   for every site.
/// - `<profile>/places.sqlite` — a single SQLite database holding **both**
///   browsing history *and bookmarks*. This detector's `reason` calls that
///   out explicitly: removing this file removes bookmarks too, not just
///   history.
///
/// `SitePreserveList` cannot be honored at file granularity for any of the
/// three above; each item's `reason` says so plainly instead of silently
/// ignoring the preserve list.
///
/// One store *does* give genuine per-site granularity: `<profile>/storage/default`
/// contains one subdirectory per origin (Firefox's Quota Manager storage,
/// backing IndexedDB, the Cache API, and other per-origin storage APIs),
/// named like `https+++example.com` (scheme and host joined by `+++`,
/// optionally followed by `+<port>` or a `^...` origin-attributes suffix
/// for container tabs). This naming scheme is a long-standing Firefox
/// implementation detail, not a documented public format, so parsing it
/// (`parseStorageOrigin`) is inherently best-effort: a directory name that
/// doesn't match the expected shape is reported as-is, unfiltered, rather
/// than guessed at. Where it does parse, this detector genuinely excludes
/// preserved sites' storage directories from the results.
///
/// This detector never opens or parses the contents of any cache/cookie/
/// history/storage file — only size, path, and modification time.
///
/// Strictly read-only. See `CoreScanEngine.Detector`.
public struct FirefoxPrivacyDetector: Detector {
    public let id = "privacy.firefox"
    public let displayName = "Firefox — cache, cookies, history & site storage"
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
        let isRunning = await runningCheck.isRunning(bundleIdentifier: BrowserBundleID.firefox)
        let runningWarning = isRunning ? ReasonText.runningWarning(browserName: "Firefox") : nil

        var items: [ScanItem] = []
        for home in HomeDirectories.resolve(context) {
            if Task.isCancelled { break }
            let profilesRoot = home + "/Library/Application Support/Firefox/Profiles"
            guard PrivacyFS.isDirectory(profilesRoot) else { continue }

            let profiles = PrivacyFS.directoryEntries(profilesRoot).filter { $0.contains(".default") }

            for profile in profiles {
                if Task.isCancelled { break }
                let profilePath = profilesRoot + "/" + profile
                guard PrivacyFS.isDirectory(profilePath) else { continue }
                items.append(contentsOf: scanMonolithicStores(profile: profile, profilePath: profilePath, runningWarning: runningWarning))
                items.append(contentsOf: scanOriginStorage(profile: profile, profilePath: profilePath, runningWarning: runningWarning))
            }
        }
        return items
    }

    private func scanMonolithicStores(profile: String, profilePath: String, runningWarning: String?) -> [ScanItem] {
        var items: [ScanItem] = []

        let cachePath = profilePath + "/cache2"
        if PrivacyFS.isDirectory(cachePath) {
            items.append(ScanItem(
                path: cachePath,
                sizeBytes: PrivacyFS.recursiveSize(of: cachePath, isCancelled: { Task.isCancelled }),
                sourceDetectorID: "privacy.firefox.cache",
                category: "Firefox — cache",
                lastUsed: PrivacyFS.modificationDate(cachePath).map { LastUsedEvidence(date: $0, source: .filesystemMTime) },
                reason: ReasonText.monolithicStore(
                    description: "Firefox's disk cache for profile '\(profile)' (hashed entry names, not organized per-site). Firefox rebuilds this automatically as you browse.",
                    preserveList: preserveList,
                    runningWarning: runningWarning
                )
            ))
        }

        let cookiesPath = profilePath + "/cookies.sqlite"
        if PrivacyFS.exists(cookiesPath), let size = PrivacyFS.fileSize(cookiesPath) {
            items.append(ScanItem(
                path: cookiesPath,
                sizeBytes: size,
                sourceDetectorID: "privacy.firefox.cookies",
                category: "Firefox — cookies",
                lastUsed: PrivacyFS.modificationDate(cookiesPath).map { LastUsedEvidence(date: $0, source: .filesystemMTime) },
                reason: ReasonText.monolithicStore(
                    description: "Firefox's cookie database for profile '\(profile)'. This will sign you out of every site, not just tracking cookies.",
                    preserveList: preserveList,
                    runningWarning: runningWarning
                )
            ))
        }

        let placesPath = profilePath + "/places.sqlite"
        if PrivacyFS.exists(placesPath), let size = PrivacyFS.fileSize(placesPath) {
            items.append(ScanItem(
                path: placesPath,
                sizeBytes: size,
                sourceDetectorID: "privacy.firefox.history",
                category: "Firefox — history",
                lastUsed: PrivacyFS.modificationDate(placesPath).map { LastUsedEvidence(date: $0, source: .filesystemMTime) },
                reason: ReasonText.monolithicStore(
                    description: "Firefox's places database for profile '\(profile)' — this holds both browsing history AND bookmarks in the same file; removing it deletes bookmarks too, not just history.",
                    preserveList: preserveList,
                    runningWarning: runningWarning
                )
            ))
        }

        return items
    }

    private func scanOriginStorage(profile: String, profilePath: String, runningWarning: String?) -> [ScanItem] {
        let storageRoot = profilePath + "/storage/default"
        guard PrivacyFS.isDirectory(storageRoot) else { return [] }

        var items: [ScanItem] = []
        for entry in PrivacyFS.directoryEntries(storageRoot) {
            if Task.isCancelled { break }
            let path = storageRoot + "/" + entry
            guard PrivacyFS.isDirectory(path) else { continue }

            let host = Self.parseStorageOrigin(entry)
            if let host, preserveList.preserves(host: host) { continue }

            var reason = host != nil
                ? "Per-site storage (IndexedDB / Cache API / other origin storage) for '\(host!)' in Firefox profile '\(profile)'. Site-specific: clearing this only affects that site's locally stored app data."
                : "Per-site storage directory '\(entry)' in Firefox profile '\(profile)'. Its name didn't match Firefox's usual '<scheme>+++<host>' origin naming pattern, so this detector could not determine which site it belongs to and cannot check it against your site preserve list."
            if let runningWarning {
                reason += " " + runningWarning
            }

            items.append(ScanItem(
                path: path,
                sizeBytes: PrivacyFS.recursiveSize(of: path, isCancelled: { Task.isCancelled }),
                sourceDetectorID: "privacy.firefox.origin-storage",
                category: "Firefox — site storage",
                lastUsed: PrivacyFS.modificationDate(path).map { LastUsedEvidence(date: $0, source: .filesystemMTime) },
                reason: reason
            ))
        }
        return items
    }

    /// Best-effort parse of a Firefox Quota Manager origin directory name
    /// (e.g. `https+++example.com`, `https+++example.com+8080`, or with a
    /// `^userContextId=...` origin-attributes suffix for container tabs)
    /// into its hostname. Returns `nil` if the name doesn't match the
    /// expected shape rather than guessing — this is a long-standing
    /// Firefox implementation detail, not a documented public format.
    static func parseStorageOrigin(_ dirName: String) -> String? {
        let base = dirName.split(separator: "^", maxSplits: 1).first.map(String.init) ?? dirName
        let comps = base.components(separatedBy: "+++")
        guard comps.count == 2, !comps[1].isEmpty else { return nil }
        let hostAndPort = comps[1]
        if let plusIndex = hostAndPort.firstIndex(of: "+") {
            let host = String(hostAndPort[hostAndPort.startIndex..<plusIndex])
            return host.isEmpty ? nil : host
        }
        return hostAndPort
    }
}
