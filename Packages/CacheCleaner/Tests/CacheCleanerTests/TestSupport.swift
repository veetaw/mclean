import Foundation
import CoreScanEngine

/// Test-only helpers for building a throwaway directory tree under the
/// system temp directory, so detector logic can be exercised without
/// touching (or depending on the state of) the real machine running the
/// test. Mirrors `DevToolsDetectorsTests.TempHome`.
enum TempHome {
    static func make() -> String {
        let path = NSTemporaryDirectory() + "CacheCleanerTests-" + UUID().uuidString
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

    /// Backdates (or forward-dates) a path's modification time, so tests can
    /// deterministically simulate "N days old" without sleeping.
    func setModificationDate(_ date: Date, at path: String) {
        try! setAttributes([.modificationDate: date], ofItemAtPath: path)
    }
}

/// A fixed reference "now" for threshold-based staleness tests, so ages can
/// be expressed as exact offsets from a stable point instead of the real
/// wall clock.
let testReferenceDate = Date(timeIntervalSince1970: 1_700_000_000)

func daysAgo(_ days: Double, from reference: Date = testReferenceDate) -> Date {
    reference.addingTimeInterval(-days * 24 * 3600)
}

func hoursAgo(_ hours: Double, from reference: Date = testReferenceDate) -> Date {
    reference.addingTimeInterval(-hours * 3600)
}

func scanContext(roots: [String]) -> ScanContext {
    ScanContext(roots: roots)
}
