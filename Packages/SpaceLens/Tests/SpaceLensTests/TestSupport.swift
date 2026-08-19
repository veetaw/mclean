import Foundation

/// Test-only helpers for building a throwaway directory tree under the
/// system temp directory, so `DirectorySizeTreeBuilder` can be exercised
/// against a real filesystem without touching (or depending on the state
/// of) the real developer machine. Mirrors `LargeOldFilesFinderTests.TempHome`.
enum TempHome {
    static func make() -> String {
        let path = NSTemporaryDirectory() + "SpaceLensTests-" + UUID().uuidString
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

    /// Creates a symbolic link, used to verify the walk never follows one.
    func makeSymlink(at linkPath: String, to destinationPath: String) {
        makeDir((linkPath as NSString).deletingLastPathComponent)
        try? removeItem(atPath: linkPath)
        try! createSymbolicLink(atPath: linkPath, withDestinationPath: destinationPath)
    }
}
