import Foundation
import CoreScanEngine

/// Test-only helpers for building a throwaway "home directory" tree under
/// the system temp directory, so detector logic can be exercised without
/// touching (or depending on the state of) the real developer machine.
enum TempHome {
    static func make() -> String {
        let path = NSTemporaryDirectory() + "DevToolsDetectorsTests-" + UUID().uuidString
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

    /// Backdates (or forward-dates) a path's modification time, so tests
    /// can deterministically simulate "N days old" without sleeping.
    func setModificationDate(_ date: Date, at path: String) {
        try! setAttributes([.modificationDate: date], ofItemAtPath: path)
    }

    /// Creates a symbolic link, used to simulate SDKMAN's/rbenv's "current
    /// version" pointer.
    func makeSymlink(at linkPath: String, to destinationPath: String) {
        makeDir((linkPath as NSString).deletingLastPathComponent)
        try? removeItem(atPath: linkPath)
        try! createSymbolicLink(atPath: linkPath, withDestinationPath: destinationPath)
    }
}

/// A fixed reference "now" for threshold-based staleness tests, so ages can
/// be expressed as exact offsets from a stable point instead of the real
/// wall clock.
let testReferenceDate = Date(timeIntervalSince1970: 1_700_000_000)

func daysAgo(_ days: Double, from reference: Date = testReferenceDate) -> Date {
    reference.addingTimeInterval(-days * 24 * 3600)
}

func scanContext(roots: [String]) -> ScanContext {
    ScanContext(roots: roots)
}
