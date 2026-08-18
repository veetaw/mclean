import CoreScanEngine

/// Convenience registry so the app layer can register every developer
/// toolchain detector with a `ScanEngine` in one call:
///
/// ```swift
/// let engine = ScanEngine()
/// await engine.register(DevToolsDetectorRegistry.all())
/// ```
///
/// See `CoreScanEngine.Detector` for the interface every detector below
/// implements, and the individual `*Detector.swift` files for what each one
/// covers (Python, Node/JS, Rust, Go, Ruby, Java/JVM, Docker, Xcode,
/// Homebrew, editor/IDE caches — per PROMPT MASTER §5.2).
public enum DevToolsDetectorRegistry {
    /// One instance of every `DevToolsDetectors` detector, built with its
    /// default thresholds. Callers that want non-default staleness
    /// thresholds (e.g. a user-configurable "treat node_modules as stale
    /// after N days" setting) should construct detectors individually
    /// instead of using this convenience list.
    public static func all() -> [Detector] {
        [
            PythonDetector(),
            NodeDetector(),
            RustDetector(),
            GoDetector(),
            RubyDetector(),
            JavaDetector(),
            DockerDetector(),
            XcodeDetector(),
            HomebrewDetector(),
            EditorDetector()
        ]
    }
}
