import CacheCleaner
import DevToolsDetectors
import DuplicateFinder
import LargeOldFilesFinder
import MobileDevDetectors
import Optimization
import PowerUserInspectors
import PrivacyCleaner
import TrashCleaner

/// `CoreScanEngine.Detector.id` sets per sidebar section, used by
/// `FindingsListView` to filter `AppEnvironment.scanSnapshotStore`'s single
/// shared snapshot. `CoreScanEngine.ScanItem`/`RemoteControlServer
/// .ScanFinding` don't carry `DetectorCategory` directly, only
/// `sourceDetectorID` — deriving the id sets from each registry (the same
/// registries `AppEnvironment.registerDefaultDetectors()` registers with
/// `ScanEngine`) keeps this filter from drifting out of sync with what's
/// actually registered.
enum FeatureDetectorIDs {
    static let devTools: Set<String> = Set(DevToolsDetectorRegistry.all().map(\.id))
    static let mobileDev: Set<String> = Set(MobileDevDetectorRegistry.allDetectors().map(\.id))
    static let powerUser: Set<String> = Set(PowerUserInspectorRegistry.allDetectors().map(\.id))
    /// Phase 5 + Phase 6, closing product spec §5.1: Trash Bins + Large &
    /// Old Files + Duplicate/Similar Files + user/system cache cleanup.
    /// Does NOT include Shredder/Uninstaller/MaintenanceScripts/SpaceLens —
    /// none of those are `Detector`s or ever part of a scan snapshot; see
    /// their own dedicated views.
    static let systemJunk: Set<String> = Set(TrashCleanerRegistry.all().map(\.id))
        .union([LargeOldFilesFinder().id])
        .union(DuplicateFinderRegistry.all().map(\.id))
        .union(CacheCleanerRegistry.all().map(\.id))
    /// Phase 6: login items / launch agents review.
    static let optimization: Set<String> = Set(OptimizationRegistry.all().map(\.id))
    /// Phase 6: browser cache/cookie/history. Built with an empty preserve
    /// list purely to enumerate detector IDs (the list doesn't affect which
    /// detectors register, only what they flag) — the real, live
    /// `AppEnvironment.privacySitePreserveList` is what's actually applied
    /// when `registerDefaultDetectors()` runs.
    static let privacy: Set<String> = Set(PrivacyCleanerRegistry.all().map(\.id))
}
