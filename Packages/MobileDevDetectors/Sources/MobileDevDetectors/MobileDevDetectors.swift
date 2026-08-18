import Foundation
import CoreScanEngine

/// Mobile dev toolchain artifact detectors — PROMPT MASTER §5.3.
///
/// Every type in this module conforms to `CoreScanEngine.Detector` and is
/// strictly read-only: it only finds and describes candidate artifacts
/// (`ScanItem`s), never deletes, moves, or modifies anything. Actual
/// deletion (behind confirmation + quarantine) lives entirely outside this
/// package, per `SAFETY_RULES.md`.
public enum MobileDevDetectorRegistry {
    /// Every detector this module ships, ready for the app layer to
    /// register with `CoreScanEngine.ScanEngine` in one call:
    ///
    /// ```swift
    /// let engine = ScanEngine()
    /// await engine.register(MobileDevDetectorRegistry.allDetectors())
    /// ```
    public static func allDetectors() -> [Detector] {
        [
            // Android
            AndroidAVDDetector(),
            AndroidSDKDetector(),
            AndroidStudioCacheDetector(),
            AndroidGradleWrapperDetector(),
            // iOS / watchOS / tvOS
            SimulatorRuntimeDetector(),
            SimulatorDeviceDataDetector(),
            CocoaPodsCacheDetector(),
            FastlaneCacheDetector()
        ]
    }

    /// Sums `ScanItem.sizeBytes` across every item produced by this
    /// module's detectors (identified via `sourceDetectorID`), for the
    /// "spazio recuperabile da toolchain mobile" dashboard figure. Items
    /// with an unknown size (`nil`) contribute 0 to the total rather than
    /// being excluded from consideration — callers that need to know
    /// whether the total is complete should separately check for items
    /// with `sizeBytes == nil`.
    ///
    /// Only counts items whose `sourceDetectorID` belongs to this module,
    /// so callers can pass either the full `ScanRunResult.items` from a
    /// mixed scan (only mobile-dev items count) or just this module's own
    /// findings.
    public static func totalRecoverableBytes(in items: [ScanItem]) -> Int64 {
        let mobileDevDetectorIDs = Set(allDetectors().map(\.id))
        return items
            .filter { mobileDevDetectorIDs.contains($0.sourceDetectorID) }
            .reduce(into: Int64(0)) { total, item in
                total += item.sizeBytes ?? 0
            }
    }
}
