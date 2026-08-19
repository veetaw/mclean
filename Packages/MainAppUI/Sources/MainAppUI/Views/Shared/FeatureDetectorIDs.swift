import DevToolsDetectors
import MobileDevDetectors
import PowerUserInspectors

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
}
