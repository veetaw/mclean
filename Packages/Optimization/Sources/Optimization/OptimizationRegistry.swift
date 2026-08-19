import CoreScanEngine

/// Convenience registry so the app layer can register every `Optimization`
/// `Detector` with a `ScanEngine` in one call, mirroring
/// `DevToolsDetectors.DevToolsDetectorRegistry` / `PowerUserInspectorRegistry`:
///
/// ```swift
/// let engine = ScanEngine()
/// await engine.register(OptimizationRegistry.all())
/// ```
///
/// Most of this module is inherently query/inspect rather than
/// find-cleanable-junk, so — like `PowerUserInspectors` — it doesn't force
/// everything into `CoreScanEngine.Detector`'s shape:
///
/// - `LaunchAgentDetector` **does** conform to `Detector` — a Launch Agent
///   plist is naturally "a filesystem artifact with a path/size," so it
///   fits the scan pipeline and lets its findings flow through
///   `SafetyRules.SafetyClassifier` like everything else.
/// - `LoginItemsInspector` and `StartupImpactReporter` are plain, directly
///   callable types instead — neither produces a single-path "found this
///   junk" result (one queries `SMAppService`/System Events state, the
///   other summarizes correlates already present on `LaunchAgentPlist`),
///   so `Detector` would be the wrong shape for them.
public enum OptimizationRegistry {
    /// The one `Detector`-conforming component this module ships.
    public static func all() -> [Detector] {
        [LaunchAgentDetector()]
    }
}
