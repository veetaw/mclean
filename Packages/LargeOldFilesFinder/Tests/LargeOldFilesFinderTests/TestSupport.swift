import Foundation
import CoreScanEngine

/// Test-only helpers for building a throwaway "home directory" tree under
/// the system temp directory, so detector logic can be exercised without
/// touching (or depending on the state of) the real developer machine.
/// Mirrors `DevToolsDetectorsTests.TempHome`.
enum TempHome {
    static func make() -> String {
        let path = NSTemporaryDirectory() + "LargeOldFilesFinderTests-" + UUID().uuidString
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
    /// exactly `sizeBytes` bytes of content.
    @discardableResult
    func makeFile(_ path: String, sizeBytes: Int) -> String {
        makeDir((path as NSString).deletingLastPathComponent)
        let data = Data(repeating: 0x41, count: sizeBytes)
        try! data.write(to: URL(fileURLWithPath: path))
        return path
    }

    /// Backdates (or forward-dates) a path's modification time, so tests
    /// can deterministically simulate "N days old" without sleeping.
    func setModificationDate(_ date: Date, at path: String) {
        try! setAttributes([.modificationDate: date], ofItemAtPath: path)
    }

    /// Creates a symbolic link, used to verify the walk never follows one.
    func makeSymlink(at linkPath: String, to destinationPath: String) {
        makeDir((linkPath as NSString).deletingLastPathComponent)
        try? removeItem(atPath: linkPath)
        try! createSymbolicLink(atPath: linkPath, withDestinationPath: destinationPath)
    }
}

/// A fixed reference "now" for threshold-based age tests, so ages can be
/// expressed as exact offsets from a stable point instead of the real wall
/// clock.
let testReferenceDate = Date(timeIntervalSince1970: 1_700_000_000)

func daysAgo(_ days: Double, from reference: Date = testReferenceDate) -> Date {
    reference.addingTimeInterval(-days * 24 * 3600)
}

func scanContext(roots: [String], maxConcurrency: Int = 4) -> ScanContext {
    ScanContext(roots: roots, maxConcurrency: maxConcurrency)
}
