import Foundation
import XCTest
@testable import PowerUserInspectors

/// Shared helpers for building throwaway fixture directory trees under a
/// per-test temp directory. Every test in this package operates entirely
/// inside its own temp directory — no test ever touches a real
/// `~/Library/...`, `/etc`, or `/Applications` path.
enum TestSupport {
    static func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PowerUserInspectorsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        // `/var` is a symlink to `/private/var` on macOS, and
        // `FileManager.enumerator`/`contentsOfDirectory` return the
        // `/private/var/...` form internally. `URL.resolvingSymlinksInPath()`
        // doesn't resolve this particular symlink, so path-equality
        // assertions would otherwise flake depending on which form a given
        // API returned. Normalize via the real `realpath(3)` instead (via
        // `PowerUserFS.realpath`, exposed to this `@testable import`).
        return URL(fileURLWithPath: PowerUserFS.realpath(url.path) ?? url.path)
    }

    @discardableResult
    static func makeDirectory(at url: URL) throws -> URL {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    static func makeFile(at url: URL, contents: String = "placeholder", modificationDate: Date? = nil) throws -> URL {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
        if let modificationDate {
            try FileManager.default.setAttributes([.modificationDate: modificationDate], ofItemAtPath: url.path)
        }
        return url
    }

    @discardableResult
    static func makeBinaryFile(at url: URL, size: Int) throws -> URL {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = Data(repeating: 0x42, count: size)
        FileManager.default.createFile(atPath: url.path, contents: data)
        return url
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

/// `ExternalCommandRunning` stub for tests: returns a canned result (or
/// `nil`, simulating "tool not found / launch failed") keyed by executable
/// name, so `PackageExplorer`/`TCCDatabaseReader`/`MDLSLastUsedDateProvider`
/// can be exercised without any of the real CLIs installed.
actor FakeCommandRunner: ExternalCommandRunning {
    struct Invocation: Equatable {
        let executable: String
        let arguments: [String]
        let currentDirectory: String?
    }

    private var resultsByExecutable: [String: ExternalCommandResult]
    private(set) var invocations: [Invocation] = []

    init(resultsByExecutable: [String: ExternalCommandResult] = [:]) {
        self.resultsByExecutable = resultsByExecutable
    }

    func setResult(_ result: ExternalCommandResult?, forExecutable executable: String) {
        resultsByExecutable[executable] = result
    }

    nonisolated func run(
        executable: String,
        arguments: [String],
        currentDirectory: String?,
        timeout: TimeInterval
    ) async -> ExternalCommandResult? {
        await recordAndResolve(executable: executable, arguments: arguments, currentDirectory: currentDirectory)
    }

    private func recordAndResolve(
        executable: String,
        arguments: [String],
        currentDirectory: String?
    ) -> ExternalCommandResult? {
        invocations.append(Invocation(executable: executable, arguments: arguments, currentDirectory: currentDirectory))
        return resultsByExecutable[executable]
    }
}

func makeResult(_ stdout: String, exitCode: Int32 = 0, stderr: String = "") -> ExternalCommandResult {
    ExternalCommandResult(standardOutput: stdout, standardError: stderr, exitCode: exitCode)
}
