import Foundation
import XCTest

/// Shared helpers for building throwaway fixture directory trees and sample
/// Launch Agent plists under a per-test temp directory. No test in this
/// package ever touches a real `~/Library/LaunchAgents` or
/// `/Library/LaunchAgents` — every fixture lives inside its own temp
/// directory, mirroring the pattern used by `MobileDevDetectorsTests` and
/// `PowerUserInspectorsTests`.
enum TestSupport {
    static func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("OptimizationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return URL(fileURLWithPath: realPath(of: url.path))
    }

    private static func realPath(of path: String) -> String {
        var buffer = [Int8](repeating: 0, count: Int(PATH_MAX))
        guard realpath(path, &buffer) != nil else { return path }
        return buffer.withUnsafeBufferPointer { ptr in
            String(cString: ptr.baseAddress!)
        }
    }

    @discardableResult
    static func makeDirectory(at url: URL) throws -> URL {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Writes a valid XML Launch Agent plist with `RunAtLoad` set as given
    /// and, optionally, `KeepAlive` as a bare boolean.
    @discardableResult
    static func makeLaunchAgentPlist(
        at url: URL,
        label: String?,
        program: String = "/usr/local/bin/example-agent",
        runAtLoad: Bool,
        keepAlive: Bool? = nil
    ) throws -> URL {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var entries = ""
        if let label {
            entries += "    <key>Label</key>\n    <string>\(label)</string>\n"
        }
        entries += "    <key>ProgramArguments</key>\n    <array>\n        <string>\(program)</string>\n    </array>\n"
        entries += "    <key>RunAtLoad</key>\n    <\(runAtLoad ? "true" : "false")/>\n"
        if let keepAlive {
            entries += "    <key>KeepAlive</key>\n    <\(keepAlive ? "true" : "false")/>\n"
        }

        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \(entries)</dict>
        </plist>
        """
        try xml.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Writes a deliberately malformed/corrupt "plist" — not valid XML or
    /// binary property list data at all — to test graceful skip-not-crash
    /// handling.
    @discardableResult
    static func makeMalformedPlist(at url: URL) throws -> URL {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let garbage = "this is { not } a valid <plist> at all — 0xDEADBEEF\n"
        try garbage.write(to: url, atomically: true, encoding: .utf8)
        return url
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
