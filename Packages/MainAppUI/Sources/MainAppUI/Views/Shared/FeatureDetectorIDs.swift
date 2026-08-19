import DevToolsDetectors
import DuplicateFinder
import LargeOldFilesFinder
import MobileDevDetectors
import PowerUserInspectors
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
    /// Phase 5, closing product spec §5.1: Trash Bins + Large & Old Files +
    /// Duplicate/Similar Files. Does NOT include Shredder — that's not a
    /// `Detector` and is never part of a scan snapshot; see `ShredderView`.
    static let systemJunk: Set<String> = Set(TrashCleanerRegistry.all().map(\.id))
        .union([LargeOldFilesFinder().id])
        .union(DuplicateFinderRegistry.all().map(\.id))
}
