import XCTest
@testable import SafetyRules

/// Covers the checkpoint 4 additions to `Denylist`: credential directories,
/// sensitive filename patterns, the non-boot-volume safe-auto downgrade
/// signal, and the dirty-git-repository check.
final class DenylistCheckpoint4Tests: XCTestCase {
    // MARK: - Credential directories

    func testCredentialDirectoriesAreForbidden() {
        let home = "/Users/testuser"
        for relative in [".ssh", ".gnupg", ".aws", ".config/gcloud", ".kube", ".azure"] {
            let path = "\(home)/\(relative)/some-file"
            XCTAssertNotNil(
                Denylist.forbiddenReason(forPath: path, homeDirectory: home),
                "expected ~/\(relative) to be forbidden"
            )
        }
    }

    func testCredentialDirectoryCheckIsHomeRelativeNotGlobal() {
        // A directory literally named ".ssh" somewhere that ISN'T under the
        // configured home directory shouldn't match — this guards against
        // an overly-broad substring check.
        let path = "/Users/someone-else/.ssh/id_rsa"
        XCTAssertNotNil(Denylist.forbiddenReason(forPath: path, homeDirectory: "/Users/someone-else"))
        XCTAssertNil(Denylist.forbiddenReason(forPath: "/Users/someone-else/not-ssh-related/id_rsa", homeDirectory: "/Users/someone-else"))
    }

    // MARK: - Sensitive filename patterns

    func testDotEnvFilesAreForbiddenEvenInsideACacheDir() {
        let path = "/Users/testuser/Library/Caches/some-build-tool/nested/.env"
        XCTAssertNotNil(Denylist.forbiddenReason(forPath: path, homeDirectory: "/Users/testuser"))
    }

    func testPemAndKeyFilesAreForbidden() {
        XCTAssertNotNil(Denylist.forbiddenReason(forPath: "/tmp/build/server.pem", homeDirectory: "/Users/testuser"))
        XCTAssertNotNil(Denylist.forbiddenReason(forPath: "/tmp/build/private.key", homeDirectory: "/Users/testuser"))
    }

    // MARK: - Non-boot volume (safe-auto downgrade signal, not forbidden)

    func testExternalVolumeIsNotForbiddenButIsFlaggedNonBoot() {
        let path = "/Volumes/MyExternalDrive/some/cache/dir"
        XCTAssertNil(Denylist.forbiddenReason(forPath: path, homeDirectory: "/Users/testuser"))
        XCTAssertTrue(Denylist.isOnNonBootVolume(path))
    }

    func testBootVolumePathsAreNotFlaggedNonBoot() {
        XCTAssertFalse(Denylist.isOnNonBootVolume("/Users/testuser/Library/Caches/foo"))
    }

    // MARK: - Dirty git repository

    func testPathInsideDirtyGitRepoIsForbidden() throws {
        let repoRoot = try makeTempGitRepo(clean: false)
        defer { try? FileManager.default.removeItem(at: repoRoot) }

        let candidatePath = repoRoot.appendingPathComponent("node_modules").path
        XCTAssertNotNil(Denylist.forbiddenReason(forPath: candidatePath, homeDirectory: "/Users/testuser"))
    }

    func testPathInsideCleanGitRepoIsNotForbiddenByTheGitCheck() throws {
        let repoRoot = try makeTempGitRepo(clean: true)
        defer { try? FileManager.default.removeItem(at: repoRoot) }

        let candidatePath = repoRoot.appendingPathComponent("node_modules").path
        XCTAssertNil(Denylist.forbiddenReason(forPath: candidatePath, homeDirectory: "/Users/testuser"))
    }

    func testPathOutsideAnyGitRepoIsUnaffectedByTheGitCheck() {
        let path = "/tmp/no-git-here-\(UUID().uuidString)/some/cache"
        XCTAssertNil(Denylist.forbiddenReason(forPath: path, homeDirectory: "/Users/testuser"))
    }

    // MARK: - Helpers

    /// Creates a real git repository in a temp directory, optionally with
    /// an uncommitted change, using the real `git` CLI (present on any Mac
    /// this test suite would run on).
    private func makeTempGitRepo(clean: Bool) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SafetyRulesGitTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("node_modules"), withIntermediateDirectories: true)

        try run("git", ["-C", root.path, "init", "-q"])
        try run("git", ["-C", root.path, "config", "user.email", "test@example.com"])
        try run("git", ["-C", root.path, "config", "user.name", "Test"])

        let trackedFile = root.appendingPathComponent("README.md")
        try "hello".write(to: trackedFile, atomically: true, encoding: .utf8)

        if clean {
            try run("git", ["-C", root.path, "add", "README.md"])
            try run("git", ["-C", root.path, "commit", "-q", "-m", "initial"])
        } else {
            // An untracked file is enough for `git status --porcelain` to
            // report the repo as dirty — no commit needed.
        }

        return root
    }

    private func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
    }
}
