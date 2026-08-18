import Foundation
import XCTest

/// Shared helpers for building throwaway fixture directory trees under a
/// per-test temp directory. Every test in this package operates entirely
/// inside its own temp directory — no test ever touches a real
/// `~/Library/...` path.
enum TestSupport {
    static func makeTempDirectory() throws -> URL {
        // `/var` is itself a symlink to `/private/var` on macOS. Resolve it
        // up front so this URL matches what `FileManager.contentsOfDirectory`
        // and friends return internally (they resolve symlinks), keeping
        // path-equality assertions in tests meaningful.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MobileDevDetectorsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        // `/var` is itself a symlink to `/private/var` on macOS, and
        // `FileManager.enumerator`/`contentsOfDirectory` return the
        // `/private/var/...` form internally. `URL.resolvingSymlinksInPath()`
        // does *not* resolve this particular symlink, so path-equality
        // assertions would otherwise flake depending on which form a given
        // API returned. Normalize via the real `realpath(3)` instead.
        return URL(fileURLWithPath: realPath(of: url.path))
    }

    private static func realPath(of path: String) -> String {
        var buffer = [Int8](repeating: 0, count: Int(PATH_MAX))
        guard realpath(path, &buffer) != nil else { return path }
        return String(cString: buffer)
    }

    @discardableResult
    static func makeDirectory(at url: URL, modificationDate: Date? = nil) throws -> URL {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        if let modificationDate {
            try setModificationDate(modificationDate, atPath: url.path)
        }
        return url
    }

    @discardableResult
    static func makeFile(at url: URL, size: Int = 128, modificationDate: Date? = nil) throws -> URL {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = Data(repeating: 0x42, count: size)
        FileManager.default.createFile(atPath: url.path, contents: data)
        if let modificationDate {
            try setModificationDate(modificationDate, atPath: url.path)
        }
        return url
    }

    static func setModificationDate(_ date: Date, atPath path: String) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: path)
    }

    static func daysAgo(_ n: Int) -> Date {
        Date().addingTimeInterval(-Double(n) * 86_400)
    }
}

/// Base class that gives every test case its own throwaway temp directory,
/// removed after each test.
class TempDirTestCase: XCTestCase {
    private(set) var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = try TestSupport.makeTempDirectory()
    }

    override func tearDownWithError() throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        tempDir = nil
        try super.tearDownWithError()
    }
}
