import XCTest
@testable import Shredder
import SafetyRules

/// All tests operate exclusively inside a per-test temp directory created in
/// `setUp` and removed in `tearDown` — nothing outside that directory is
/// ever read from or written to.
final class ShredderTests: XCTestCase {
    private var tempDirectory: URL!
    private var shredder: Shredder!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShredderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        tempDirectory = base
        shredder = Shredder()
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        shredder = nil
        try super.tearDownWithError()
    }

    private func makeFile(named name: String = "target.txt", content: Data) throws -> URL {
        let url = tempDirectory.appendingPathComponent(name)
        try content.write(to: url)
        return url
    }

    /// Small helper so call sites read like `XCTAssertThrowsError` but work
    /// with `Shredder`'s `async` actor-isolated methods.
    private func assertThrowsShredError<T>(
        _ expression: @autoclosure () async throws -> T,
        _ message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line,
        _ errorHandler: (ShredError) -> Void
    ) async {
        do {
            _ = try await expression()
            XCTFail(message.isEmpty ? "Expected an error to be thrown" : message, file: file, line: line)
        } catch let error as ShredError {
            errorHandler(error)
        } catch {
            XCTFail("Expected a ShredError, got \(error)", file: file, line: line)
        }
    }

    // MARK: - requestShred validation

    func testRequestShredRefusesForbiddenPath() async throws {
        // `.pem` is a hardcoded Denylist filename pattern — genuinely
        // forbidden per `SafetyRules.Denylist.forbiddenReason`, not a
        // fake/simulated prefix. Confirm the denylist really does match
        // this path first, then confirm Shredder refuses it for the same
        // reason.
        let url = try makeFile(named: "identity.pem", content: Data("secret".utf8))
        XCTAssertNotNil(
            Denylist.forbiddenReason(forPath: url.path),
            "Precondition: Denylist must actually forbid this path for the test to be meaningful."
        )

        await assertThrowsShredError(try await self.shredder.requestShred(path: url.path)) { error in
            guard case .pathForbidden = error else {
                return XCTFail("Expected .pathForbidden, got \(error)")
            }
        }

        // Refusal must not touch the file at all.
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    /// NOTE: this deliberately does not go through `Shredder` itself.
    /// `Denylist.forbiddenReason`'s credential-directory branch (`~/.ssh`
    /// etc.) is relative to a `homeDirectory` parameter that defaults to
    /// `NSHomeDirectory()`; `Shredder` always uses that real default (same
    /// as `FileSystemQuarantineManager`) and exposes no override, so a test
    /// can't safely point it at a fake home directory without mutating
    /// process-global state (`$HOME`) that could leak into other tests.
    /// This asserts the primitive `Shredder.requestShred` relies on
    /// (already covered end-to-end at the `Denylist` level in
    /// `SafetyRulesTests`); the `.pem`/`.key` filename-pattern tests above
    /// and below exercise the same `forbiddenReason` call path through
    /// `Shredder` itself using paths that don't require a fake home.
    func testCredentialDirectoryDenylistPrimitiveShredderReliesOn() throws {
        let fakeHome = tempDirectory.appendingPathComponent("fake-home", isDirectory: true)
        let sshDir = fakeHome.appendingPathComponent(".ssh", isDirectory: true)
        try FileManager.default.createDirectory(at: sshDir, withIntermediateDirectories: true)
        let keyPath = sshDir.appendingPathComponent("id_ed25519").path

        XCTAssertNotNil(Denylist.forbiddenReason(forPath: keyPath, homeDirectory: fakeHome.path))
    }

    func testRequestShredRefusesNonexistentPath() async throws {
        let missing = tempDirectory.appendingPathComponent("does-not-exist.txt").path

        await assertThrowsShredError(try await self.shredder.requestShred(path: missing)) { error in
            guard case .sourceNotFound = error else {
                return XCTFail("Expected .sourceNotFound, got \(error)")
            }
        }
    }

    func testRequestShredRefusesDirectory() async throws {
        let dir = tempDirectory.appendingPathComponent("a-directory", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        await assertThrowsShredError(try await self.shredder.requestShred(path: dir.path)) { error in
            guard case .isDirectory = error else {
                return XCTFail("Expected .isDirectory, got \(error)")
            }
        }
    }

    func testRequestShredRefusesSymbolicLink() async throws {
        let real = try makeFile(named: "real.txt", content: Data("hello".utf8))
        let link = tempDirectory.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        await assertThrowsShredError(try await self.shredder.requestShred(path: link.path)) { error in
            guard case .isSymbolicLink = error else {
                return XCTFail("Expected .isSymbolicLink, got \(error)")
            }
        }

        // The link's target must be completely untouched by the refusal.
        XCTAssertEqual(try Data(contentsOf: real), Data("hello".utf8))
    }

    func testDistinctErrorsAreNotCollapsed() async throws {
        // Sanity check that the three rejection reasons above really do
        // produce three *different* error cases, not one generic failure.
        let missing = tempDirectory.appendingPathComponent("nope.txt").path
        let dir = tempDirectory.appendingPathComponent("dir", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let forbidden = try makeFile(named: "secret.key", content: Data("x".utf8))

        func caseName(_ path: String) async -> String {
            do {
                _ = try await shredder.requestShred(path: path)
                return "no error"
            } catch let error as ShredError {
                switch error {
                case .sourceNotFound: return "sourceNotFound"
                case .isDirectory: return "isDirectory"
                case .pathForbidden: return "pathForbidden"
                case .isSymbolicLink: return "isSymbolicLink"
                case .invalidPassCount: return "invalidPassCount"
                case .cancelled: return "cancelled"
                case .underlying: return "underlying"
                }
            } catch {
                return "other"
            }
        }

        let names = Set(await [caseName(missing), caseName(dir.path), caseName(forbidden.path)])
        XCTAssertEqual(names, ["sourceNotFound", "isDirectory", "pathForbidden"])
    }

    // MARK: - confirmShred destroys the file

    func testConfirmShredDeletesFile() async throws {
        let url = try makeFile(content: Data("some file content to destroy".utf8))
        let request = try await shredder.requestShred(path: url.path)

        try await shredder.confirmShred(request, passes: 3)

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testConfirmShredDeletesEmptyFile() async throws {
        let url = try makeFile(content: Data())
        let request = try await shredder.requestShred(path: url.path)

        try await shredder.confirmShred(request, passes: 3)

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testConfirmShredRejectsInvalidPassCount() async throws {
        let url = try makeFile(content: Data("content".utf8))
        let request = try await shredder.requestShred(path: url.path)

        do {
            try await shredder.confirmShred(request, passes: 0)
            XCTFail("Expected invalidPassCount to be thrown")
        } catch ShredError.invalidPassCount(let passes) {
            XCTAssertEqual(passes, 0)
        }

        // Rejected before any I/O — file must be untouched.
        XCTAssertEqual(try Data(contentsOf: url), Data("content".utf8))
    }

    // MARK: - confirmShred re-validates the denylist (defense in depth)

    /// The same path can become forbidden between `requestShred` and
    /// `confirmShred` without any rename or symlink swap at all: a git
    /// repository that's clean (not forbidden) when requested can be
    /// dirtied (forbidden — see `Denylist.dirtyGitRepositoryReason`) before
    /// it's confirmed. This is exactly the realistic "stale request"
    /// scenario the re-check exists for, using the same "dirty-git-repo
    /// file" example the task called out explicitly.
    func testConfirmShredRejectsPathThatBecameForbiddenSinceRequest() async throws {
        let repoDir = tempDirectory.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repoDir, withIntermediateDirectories: true)
        try runGit(["init"], in: repoDir)
        try runGit(["config", "user.email", "test@example.com"], in: repoDir)
        try runGit(["config", "user.name", "Test"], in: repoDir)

        let fileURL = repoDir.appendingPathComponent("committed.txt")
        try Data("committed content".utf8).write(to: fileURL)
        try runGit(["add", "."], in: repoDir)
        try runGit(["commit", "-m", "initial"], in: repoDir)

        // Repo is clean at request time — must succeed.
        let request = try await shredder.requestShred(path: fileURL.path)

        // Dirty the repo (uncommitted change) before confirming.
        try Data("modified content, uncommitted".utf8).write(to: fileURL)

        do {
            try await shredder.confirmShred(request, passes: 1)
            XCTFail("Expected confirmShred to reject a path that became part of a dirty git repo since the request")
        } catch ShredError.pathForbidden {
            // expected
        }

        XCTAssertEqual(try Data(contentsOf: fileURL), Data("modified content, uncommitted".utf8))
    }

    func testConfirmShredRejectsSymlinkSwappedInAfterRequest() async throws {
        // Request against an ordinary regular file, then — before
        // confirming — replace the directory entry at that exact path with
        // a symbolic link. `confirmShred` must catch this independently
        // rather than trusting the request's cached state.
        let path = tempDirectory.appendingPathComponent("swapped.txt")
        try Data("original".utf8).write(to: path)
        let request = try await shredder.requestShred(path: path.path)

        try FileManager.default.removeItem(at: path)
        let elsewhere = try makeFile(named: "elsewhere.txt", content: Data("other file".utf8))
        try FileManager.default.createSymbolicLink(at: path, withDestinationURL: elsewhere)

        do {
            try await shredder.confirmShred(request, passes: 1)
            XCTFail("Expected confirmShred to reject a path that became a symlink after requestShred")
        } catch ShredError.isSymbolicLink {
            // expected
        }

        // The file the swapped-in symlink points at must be untouched.
        XCTAssertEqual(try Data(contentsOf: elsewhere), Data("other file".utf8))
    }

    // MARK: - overwrite actually happens before deletion

    /// Reference-type box for collecting results from `confirmShred`'s
    /// `@Sendable` progress callback, which strict concurrency won't allow
    /// capturing plain `var`s into. Only ever touched synchronously, from
    /// inside the callback (which itself only ever runs on the `Shredder`
    /// actor, serialized with respect to itself) and then read back on the
    /// test's own task after `confirmShred` has returned — never
    /// concurrently, so `@unchecked Sendable` is accurate here, not a way
    /// to paper over an actual race.
    private final class ObservationBox<Value>: @unchecked Sendable {
        var value: Value
        init(_ value: Value) { self.value = value }
    }

    func testConfirmShredOverwritesContentBeforeDeleting() async throws {
        // Distinctive, non-zero, non-0xFF original content so pass 1
        // (all-zero) is unambiguous when observed.
        let original = Data(repeating: 0x41, count: 256 * 1024) // 'A' * 256KiB
        let url = try makeFile(content: original)
        let request = try await shredder.requestShred(path: url.path)

        let observedAfterPass1 = ObservationBox<Data?>(nil)
        let passesSeen = ObservationBox<[Int]>([])

        try await shredder.confirmShred(request, passes: 3) { completed, total in
            passesSeen.value.append(completed)
            if completed == 1 {
                // Read directly from disk at this checkpoint: the file must
                // still exist (not yet deleted) and its content must
                // already differ from the original (pass 1 = all zero).
                observedAfterPass1.value = try? Data(contentsOf: url)
            }
            XCTAssertEqual(total, 3)
        }

        XCTAssertEqual(passesSeen.value, [1, 2, 3], "Expected exactly one callback per pass, in order")

        guard let observed = observedAfterPass1.value else {
            return XCTFail("Expected to observe file content after pass 1")
        }
        XCTAssertEqual(observed.count, original.count, "Size must be unchanged mid-shred (truncation only happens at the very end)")
        XCTAssertNotEqual(observed, original, "Content must already be overwritten after pass 1")
        XCTAssertEqual(observed, Data(repeating: 0x00, count: original.count), "Pass 1 must be the all-zero pattern")

        // And only *after* all passes completed is the file actually gone.
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testConfirmShredPass2IsAllOnes() async throws {
        let original = Data(repeating: 0x41, count: 64 * 1024)
        let url = try makeFile(content: original)
        let request = try await shredder.requestShred(path: url.path)

        let observedAfterPass2 = ObservationBox<Data?>(nil)
        try await shredder.confirmShred(request, passes: 3) { completed, _ in
            if completed == 2 {
                observedAfterPass2.value = try? Data(contentsOf: url)
            }
        }

        XCTAssertEqual(observedAfterPass2.value, Data(repeating: 0xFF, count: original.count))
    }

    // MARK: - cancellation leaves a safe, sensible state

    func testCancellationBeforeAnyPassLeavesFileFullyIntactAndUndeleted() async throws {
        let original = Data(repeating: 0x41, count: 64 * 1024)
        let url = try makeFile(content: original)
        let request = try await shredder.requestShred(path: url.path)

        // Capture the actor itself (a `Sendable` type) into a local
        // constant rather than reaching through `self` inside the `Task`
        // closure below — `self` is the (non-`Sendable`) `XCTestCase`, and
        // Swift 6 strict concurrency rightly flags capturing it into a
        // concurrently-executing closure.
        let localShredder = shredder!
        let task = Task {
            try await localShredder.confirmShred(request, passes: 5)
        }
        task.cancel()

        do {
            try await task.value
            XCTFail("Expected cancellation to surface as ShredError.cancelled")
        } catch let error as ShredError {
            guard case .cancelled(let path, let passesCompleted, let totalPasses) = error else {
                return XCTFail("Expected .cancelled, got \(error)")
            }
            XCTAssertEqual(path, url.path)
            XCTAssertEqual(totalPasses, 5)
            XCTAssertLessThanOrEqual(passesCompleted, 1, "Cancelled essentially immediately, so at most the in-flight first pass could have completed")
        }

        // Regardless of how many passes (0 or 1) squeezed in before the
        // cancellation flag was observed, the file must never be deleted
        // or truncated by a cancelled operation, and must remain exactly
        // its original size.
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let sizeAfter = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int
        XCTAssertEqual(sizeAfter, original.count)
    }

    func testCancellationAfterFirstPassStillLeavesFileUndeletedButContentDestroyed() async throws {
        // A large-enough file that pass 1 takes measurably long (spans many
        // 4MiB chunks), so cancellation requested right after pass 1's
        // callback fires lands during pass 2, not after everything.
        let original = Data(repeating: 0x41, count: 24 * 1024 * 1024) // 24 MiB
        let url = try makeFile(content: original)
        let request = try await shredder.requestShred(path: url.path)

        // Reference box so the in-flight task can cancel *itself* once its
        // own progress callback reports pass 1 done. Assigning `box.task`
        // happens on the calling thread immediately after `Task { }`
        // returns its handle — long before a 24MiB pass 1 write can finish
        // — so there's no meaningful race with the cancellation check below.
        let box = ObservationBox<Task<Void, Error>?>(nil)
        let localShredder = shredder!
        let task = Task {
            try await localShredder.confirmShred(request, passes: 3) { completed, _ in
                if completed == 1 {
                    box.value?.cancel()
                }
            }
        }
        box.value = task

        do {
            try await task.value
        } catch let error as ShredError {
            guard case .cancelled(let path, let passesCompleted, _) = error else {
                return XCTFail("Expected .cancelled or success, got \(error)")
            }
            XCTAssertEqual(path, url.path)
            XCTAssertGreaterThanOrEqual(passesCompleted, 1)
        }

        // Whether it finished (fast machine, race lost) or was cancelled,
        // the file must never end up as a corrupted, wrong-length artifact:
        // either it's fully gone (finished) or it's present at its
        // original length (cancelled mid-way).
        if FileManager.default.fileExists(atPath: url.path) {
            let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int
            XCTAssertEqual(size, original.count)
            let content = try Data(contentsOf: url)
            XCTAssertNotEqual(content, original, "At least pass 1 had completed, so original content must already be gone")
        }
    }

    // MARK: - ShredRequest cannot be fabricated

    func testShredRequestHasNoAccessiblePublicInitializer() {
        // This is intentionally not a runtime assertion: `ShredRequest`'s
        // initializer is `fileprivate` to `Shredder.swift`, so no code in
        // this test file (a different file, even under `@testable import`,
        // since fileprivate/private access is scoped to the source file,
        // not lifted by testability the way `internal` is) can write
        // `ShredRequest(path:fileSizeBytes:requestedAt:)` at all — it would
        // fail to compile, not fail an assertion. The type system is the
        // test here.
    }
}

/// Runs `git <args>` synchronously inside `directory`, only ever within a
/// test's own temp directory, and fails the calling test on a non-zero exit.
private func runGit(_ args: [String], in directory: URL, file: StaticString = #filePath, line: UInt = #line) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["git", "-C", directory.path] + args
    let errorPipe = Pipe()
    process.standardError = errorPipe
    process.standardOutput = Pipe()
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let message = String(data: errorData, encoding: .utf8) ?? "<no output>"
        XCTFail("git \(args.joined(separator: " ")) failed: \(message)", file: file, line: line)
        throw ShredderTestSetupError.gitFailed(message)
    }
}

private enum ShredderTestSetupError: Error {
    case gitFailed(String)
}
