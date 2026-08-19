import Foundation
import CoreScanEngine

/// Safari cache/cookie/history scan.
///
/// ## Known limitations — read before trusting this detector
///
/// Every store this detector reports on is a **single opaque store covering
/// every site Safari has ever visited**, not one file per site:
///
/// - `~/Library/Caches/com.apple.Safari` — Safari's whole browser cache
///   directory. Its internal layout (`fsCachedData`, `WebKitCache`, ...) is
///   an undocumented WebKit implementation detail and is not organized
///   per-origin in any stable, human-readable way this detector can rely
///   on, so it is reported as one whole directory.
/// - `~/Library/Cookies/Cookies.binarycookies` — a single binary cookie jar
///   (Apple's private `.binarycookies` format) holding cookies for every
///   site at once.
/// - `~/Library/Safari/History.db` — a single SQLite database holding
///   browsing history for every site at once.
///
/// Because of that, `SitePreserveList` **cannot be honored at file
/// granularity for any Safari store** — there is no per-site subdirectory
/// to exclude. Rather than silently ignore the user's preserve-list intent,
/// each item's `reason` says plainly that a preserved site's data may be
/// inside it and that cleaning it affects every site in that store. This
/// detector never opens or parses any of these files' contents — only
/// their size and modification time.
///
/// Strictly read-only. See `CoreScanEngine.Detector`.
public struct SafariPrivacyDetector: Detector {
    public let id = "privacy.safari"
    public let displayName = "Safari — cache, cookies & history"
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
        let isRunning = await runningCheck.isRunning(bundleIdentifier: BrowserBundleID.safari)
        let runningWarning = isRunning ? ReasonText.runningWarning(browserName: "Safari") : nil

        var items: [ScanItem] = []
        for home in HomeDirectories.resolve(context) {
            if Task.isCancelled { break }

            let cachePath = home + "/Library/Caches/com.apple.Safari"
            if PrivacyFS.isDirectory(cachePath) {
                items.append(ScanItem(
                    path: cachePath,
                    sizeBytes: PrivacyFS.recursiveSize(of: cachePath, isCancelled: { Task.isCancelled }),
                    sourceDetectorID: "privacy.safari.cache",
                    category: "Safari — cache",
                    lastUsed: PrivacyFS.modificationDate(cachePath).map { LastUsedEvidence(date: $0, source: .filesystemMTime) },
                    reason: ReasonText.monolithicStore(
                        description: "Safari's browser cache directory (cached page resources, WebKit disk cache). Safari rebuilds this automatically as you browse.",
                        preserveList: preserveList,
                        runningWarning: runningWarning
                    )
                ))
            }

            let cookiesPath = home + "/Library/Cookies/Cookies.binarycookies"
            if PrivacyFS.exists(cookiesPath), let size = PrivacyFS.fileSize(cookiesPath) {
                items.append(ScanItem(
                    path: cookiesPath,
                    sizeBytes: size,
                    sourceDetectorID: "privacy.safari.cookies",
                    category: "Safari — cookies",
                    lastUsed: PrivacyFS.modificationDate(cookiesPath).map { LastUsedEvidence(date: $0, source: .filesystemMTime) },
                    reason: ReasonText.monolithicStore(
                        description: "Safari's binary cookie jar. This will sign you out of every site and clear every site preference stored as a cookie, not just tracking cookies.",
                        preserveList: preserveList,
                        runningWarning: runningWarning
                    )
                ))
            }

            let historyPath = home + "/Library/Safari/History.db"
            if PrivacyFS.exists(historyPath), let size = PrivacyFS.fileSize(historyPath) {
                items.append(ScanItem(
                    path: historyPath,
                    sizeBytes: size,
                    sourceDetectorID: "privacy.safari.history",
                    category: "Safari — history",
                    lastUsed: PrivacyFS.modificationDate(historyPath).map { LastUsedEvidence(date: $0, source: .filesystemMTime) },
                    reason: ReasonText.monolithicStore(
                        description: "Safari's browsing history database.",
                        preserveList: preserveList,
                        runningWarning: runningWarning
                    )
                ))
            }
        }
        return items
    }
}
