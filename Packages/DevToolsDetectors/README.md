# DevToolsDetectors

Placeholder — scope for `Agent:DevToolsDetectors` (Phase 1).

Implements `CoreScanEngine.Detector` for each toolchain in PROMPT MASTER §5.2:
Python, Node/JS, Rust, Go, Ruby, Java/JVM, Docker, Xcode, Homebrew, editor/IDE
caches. Read-only: finds and evaluates "last real use", never deletes.

One file per toolchain (e.g. `PythonDetector.swift`, `NodeDetector.swift`),
each conforming to `Detector` and registered with `ScanEngine` by the app
layer. See `CoreScanEngine/Sources/CoreScanEngine/Detector.swift` for the
interface to implement.
