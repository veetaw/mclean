import CoreScanEngine

/// Convenience registry so the app layer can register every duplicate/
/// similar-file detector with a `ScanEngine` in one call:
///
/// ```swift
/// let engine = ScanEngine()
/// await engine.register(DuplicateFinderRegistry.all())
/// ```
///
/// See `CoreScanEngine.Detector` for the interface both detectors below
/// implement: `ExactDuplicateDetector` (hash-based, byte-identical files of
/// any type) and `SimilarImageDetector` (perceptual-hash-based, visually
/// near-identical photos) — per PROMPT MASTER §5.1.
public enum DuplicateFinderRegistry {
    /// One instance of each `DuplicateFinder` detector, built with its
    /// default thresholds. Callers that want non-default thresholds (e.g. a
    /// user-configurable perceptual-similarity strictness setting) should
    /// construct detectors individually instead of using this convenience
    /// list.
    public static func all() -> [Detector] {
        [
            ExactDuplicateDetector(),
            SimilarImageDetector()
        ]
    }
}
