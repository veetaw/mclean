import CoreScanEngine

/// System Junk detectors — PROMPT MASTER §5.1: user/app cache, user-writable
/// logs, per-user temp files, incomplete downloads, and unused language
/// packs.
///
/// Every type in this module conforms to `CoreScanEngine.Detector` and is
/// strictly read-only: it only finds and describes candidate artifacts
/// (`ScanItem`s), never deletes, moves, or modifies anything. Every
/// detector's findings flow through `SafetyRules.SafetyClassifier` at a
/// single chokepoint upstream in `MainAppUI` before anything is ever offered
/// for quarantine — this package does not duplicate any of that
/// classification logic (denylist, credential directories, dirty-git-repo
/// check, non-boot-volume downgrade, ...); see `SAFETY_RULES.md`.
///
/// Deliberately **not** covered by this package (see each detector's doc
/// comment for the specific reasoning):
/// - Root-owned system logs (`/var/log` and similar) — requires privileged
///   access via a `PrivilegedHelper` executable that doesn't exist yet.
/// - Developer-toolchain caches already owned by `DevToolsDetectors` and
///   `MobileDevDetectors` (pip, Homebrew, JetBrains, Yarn, CocoaPods,
///   fastlane, Android Studio, ...) — see `UserAppCacheDetector`'s
///   `excludedTopLevelNames`.
public enum CacheCleanerRegistry {
    /// One instance of every `CacheCleaner` detector, built with its default
    /// thresholds. Callers that want non-default staleness/size thresholds
    /// (e.g. a user-configurable "treat caches as stale after N days"
    /// setting) should construct detectors individually instead of using
    /// this convenience list.
    public static func all() -> [Detector] {
        [
            UserAppCacheDetector(),
            UserLogDetector(),
            TempFilesDetector(),
            IncompleteDownloadDetector(),
            LanguagePackDetector()
        ]
    }
}
