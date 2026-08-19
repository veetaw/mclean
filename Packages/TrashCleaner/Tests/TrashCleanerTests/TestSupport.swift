import Foundation
import CoreScanEngine

/// Test-only helpers for building throwaway directory trees under the
/// system temp directory, so detector logic can be exercised without
/// touching (or depending on the state of) the real developer machine —
/// in particular, without ever reading the real `~/.Trash`, mounted
/// volumes, `~/Library/Mail`, or `~/Pictures`.
enum TempHome {
    static func make() -> String {
        let path = NSTemporaryDirectory() + "TrashCleanerTests-" + UUID().uuidString
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
