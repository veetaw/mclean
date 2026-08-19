import CoreScanEngine

/// Convenience registry so the app layer can register every Privacy
/// Cleaner detector with a `ScanEngine` in one call:
///
/// ```swift
/// let engine = ScanEngine()
/// await engine.register(PrivacyCleanerRegistry.all(preserveList: mySitePreserveList))
/// ```
///
/// Covers Safari, Chrome, and Firefox cache/cookie/history — per PROMPT
/// MASTER §5.1 ("Privacy cleaner: cache/cookie/history browser, con
/// whitelist per siti da preservare"). See `CoreScanEngine.Detector` for
/// the interface every detector below implements, and each individual
/// `*PrivacyDetector.swift` file for exactly what it covers and — for the
/// monolithic cookie-jar/history-database/cache stores every browser here
/// has — the documented limits on how (and whether) `SitePreserveList` can
/// be honored for that specific store.
///
/// All three detectors also check, per browser, whether that browser's
/// process currently appears to be running (`RunningBrowserCheck`,
/// `NSWorkspace.shared.runningApplications`) and — if so — say so plainly
/// in `ScanItem.reason` rather than silently proceeding as if quarantining
/// a live browser's open files were as safe as a closed browser's. This
/// never suppresses an item outright; it only makes the risk visible.
public enum PrivacyCleanerRegistry {
    /// One instance of every `PrivacyCleaner` detector, sharing the same
    /// `preserveList` and `runningCheck`. Callers that want different
    /// preserve lists per browser (unlikely, but possible) should construct
    /// detectors individually instead of using this convenience list.
    public static func all(
        preserveList: SitePreserveList = SitePreserveList(),
        runningCheck: RunningBrowserCheck = RunningBrowserCheck()
    ) -> [Detector] {
        [
            SafariPrivacyDetector(preserveList: preserveList, runningCheck: runningCheck),
            ChromePrivacyDetector(preserveList: preserveList, runningCheck: runningCheck),
            FirefoxPrivacyDetector(preserveList: preserveList, runningCheck: runningCheck)
        ]
    }
}
