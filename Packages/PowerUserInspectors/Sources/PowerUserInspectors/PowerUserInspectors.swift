import CoreScanEngine

/// Power User inspectors — PROMPT MASTER §5.4: installed-apps inventory,
/// best-effort TCC permission listing, a backed-up config file explorer,
/// per-language package explorers, and a JSON system report.
///
/// Most of this section is inherently query/inspect rather than
/// find-cleanable-junk, so it doesn't force everything into
/// `CoreScanEngine.Detector`'s "cleanable item" shape:
///
/// - `InstalledAppsDetector` **does** conform to `Detector` — an installed
///   app is naturally "a filesystem artifact with a size and a last-used
///   date", so it fits the model and lets the app layer fold it into the
///   same scan pipeline as everything else (its `ScanItem.reason` is
///   descriptive inventory, not a removal suggestion).
/// - `TCCDatabaseReader` / `TCCSettingsPaneOpener`, `ConfigFileExplorer`,
///   `PackageExplorer`, and `SystemReportExporter` are plain, directly
///   callable types instead — none of them produce a single-path "found
///   this junk" result, so `Detector` would be the wrong shape for them.
public enum PowerUserInspectorRegistry {
    /// The one `Detector`-conforming inspector this module ships, ready for
    /// the app layer to register with `CoreScanEngine.ScanEngine`:
    ///
    /// ```swift
    /// let engine = ScanEngine()
    /// await engine.register(PowerUserInspectorRegistry.allDetectors())
    /// ```
    public static func allDetectors() -> [Detector] {
        [InstalledAppsDetector()]
    }
}
