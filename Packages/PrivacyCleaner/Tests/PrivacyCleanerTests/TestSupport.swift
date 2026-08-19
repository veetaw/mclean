import Foundation
import CoreScanEngine
import PrivacyCleaner

/// Test-only helpers for building a throwaway "home directory" tree under
/// the system temp directory, so detector logic can be exercised without
/// touching (or depending on the state of) the real developer machine.
enum TempHome {
    static func make() -> String {
        let path = NSTemporaryDirectory() + "PrivacyCleanerTests-" + UUID().uuidString
        try! FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }

    static func cleanup(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }
}

extension FileManager {
    /// Creates every intermediate directory component of `path`.
    func makeDir(_ path: String) {
        try! createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    /// Creates a file at `path` (and any missing parent directories) with
    /// the given text contents.
    func makeFile(_ path: String, contents: String = "placeholder") {
        makeDir((path as NSString).deletingLastPathComponent)
        try! contents.data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
    }
}

func scanContext(roots: [String]) -> ScanContext {
    ScanContext(roots: roots)
}

/// A `RunningBrowserCheck` that never reports anything as running, for
/// tests that don't care about that behavior.
func neverRunning() -> RunningBrowserCheck {
    RunningBrowserCheck(runningBundleIdentifiers: { [] })
}

/// A `RunningBrowserCheck` that reports exactly the given bundle
/// identifiers as running.
func alwaysRunning(_ bundleIdentifiers: Set<String>) -> RunningBrowserCheck {
    RunningBrowserCheck(runningBundleIdentifiers: { bundleIdentifiers })
}
