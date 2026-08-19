import XCTest
@testable import PowerUserInspectors

final class ConfigFileExplorerTests: TempDirTestCase {
    private var etcDir: URL!
    private var homeDir: URL!
    private var backupDir: URL!
    private var explorer: ConfigFileExplorer!

    override func setUpWithError() throws {
        try super.setUpWithError()
        etcDir = tempDir.appendingPathComponent("etc")
        homeDir = tempDir.appendingPathComponent("home")
        backupDir = tempDir.appendingPathComponent("backups")
        try TestSupport.makeDirectory(at: etcDir)
        try TestSupport.makeDirectory(at: homeDir)
        explorer = ConfigFileExplorer(etcDirectory: etcDir, homeDirectory: homeDir, backupDirectory: backupDir)
    }

    // MARK: - Listing

    func testListEntriesInEtcReportsMetadataAndGuessedSyntax() throws {
        try TestSupport.makeFile(at: etcDir.appendingPathComponent("hosts"), contents: "127.0.0.1 localhost\n")
        try TestSupport.makeFile(at: etcDir.appendingPathComponent("some.json"), contents: "{}")
        try TestSupport.makeDirectory(at: etcDir.appendingPathComponent("subdir"))

        let entries = explorer.listEntries(in: .etc)
        XCTAssertEqual(Set(entries.map(\.name)), ["hosts", "some.json", "subdir"])

        let hosts = try XCTUnwrap(entries.first { $0.name == "hosts" })
        XCTAssertFalse(hosts.isDirectory)
        XCTAssertEqual(hosts.guessedSyntax, .plainText)
        XCTAssertNotNil(hosts.sizeBytes)
        XCTAssertGreaterThan(hosts.sizeBytes ?? 0, 0)
        XCTAssertNotNil(hosts.modificationDate)

        let json = try XCTUnwrap(entries.first { $0.name == "some.json" })
        XCTAssertEqual(json.guessedSyntax, .json)

        let subdir = try XCTUnwrap(entries.first { $0.name == "subdir" })
        XCTAssertTrue(subdir.isDirectory)
        XCTAssertNil(subdir.sizeBytes)
    }

    func testListEntriesInUserConfigListsDotConfigContents() throws {
        try TestSupport.makeFile(at: homeDir.appendingPathComponent(".config/tool/settings.toml"), contents: "x = 1")

        let entries = explorer.listEntries(in: .userConfig)
        XCTAssertEqual(entries.map(\.name), ["tool"])
        XCTAssertTrue(entries[0].isDirectory)
    }

    func testListEntriesInHomeDotfilesOnlyReturnsDotfiles() throws {
        try TestSupport.makeFile(at: homeDir.appendingPathComponent(".zshrc"), contents: "export PATH=$PATH")
        try TestSupport.makeFile(at: homeDir.appendingPathComponent(".gitconfig"), contents: "[user]\nname = x")
        try TestSupport.makeFile(at: homeDir.appendingPathComponent("Documents/notes.txt"), contents: "hi")

        let entries = explorer.listEntries(in: .homeDotfiles)
        let names = Set(entries.map(\.name))
        XCTAssertTrue(names.contains(".zshrc"))
        XCTAssertTrue(names.contains(".gitconfig"))
        XCTAssertFalse(names.contains("Documents"))

        let zshrc = try XCTUnwrap(entries.first { $0.name == ".zshrc" })
        XCTAssertEqual(zshrc.guessedSyntax, .shell)
        let gitconfig = try XCTUnwrap(entries.first { $0.name == ".gitconfig" })
        XCTAssertEqual(gitconfig.guessedSyntax, .gitconfig)
    }

    func testListEntriesOnMissingDirectoryReturnsEmpty() {
        XCTAssertEqual(explorer.listEntries(atDirectory: tempDir.appendingPathComponent("nope").path), [])
    }

    // MARK: - Reading

    func testReadContentsReturnsFileText() throws {
        let file = etcDir.appendingPathComponent("hosts")
        try TestSupport.makeFile(at: file, contents: "127.0.0.1 localhost\n")

        XCTAssertEqual(try explorer.readContents(at: file.path), "127.0.0.1 localhost\n")
    }

    func testReadContentsThrowsForMissingFile() {
        XCTAssertThrowsError(try explorer.readContents(at: etcDir.appendingPathComponent("missing").path)) { error in
            guard case ConfigFileExplorerError.fileNotFound = error else {
                return XCTFail("expected fileNotFound, got \(error)")
            }
        }
    }

    func testReadContentsThrowsForDirectory() throws {
        let dir = etcDir.appendingPathComponent("adir")
        try TestSupport.makeDirectory(at: dir)
        XCTAssertThrowsError(try explorer.readContents(at: dir.path)) { error in
            guard case ConfigFileExplorerError.notARegularFile = error else {
                return XCTFail("expected notARegularFile, got \(error)")
            }
        }
    }

    // MARK: - Writing always backs up first

    func testWriteToExistingFileBacksUpOriginalContentBeforeOverwriting() throws {
        let file = etcDir.appendingPathComponent("hosts")
        try TestSupport.makeFile(at: file, contents: "original contents\n")

        let receipt = try explorer.write(newContents: "new contents\n", to: file.path)

        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "new contents\n")

        let backupPath = try XCTUnwrap(receipt.backupPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupPath))
        XCTAssertEqual(try String(contentsOfFile: backupPath, encoding: .utf8), "original contents\n")
        XCTAssertEqual(receipt.originalPath, file.path)
    }

    func testWriteToNewFileHasNoBackupPathSinceThereWasNothingToBackUp() throws {
        let file = etcDir.appendingPathComponent("brand-new.conf")
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))

        let receipt = try explorer.write(newContents: "hello\n", to: file.path)

        XCTAssertNil(receipt.backupPath)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "hello\n")
    }

    func testMultipleWritesProduceMultipleVersionedBackups() throws {
        let file = etcDir.appendingPathComponent("hosts")
        try TestSupport.makeFile(at: file, contents: "v1\n")

        let receipt1 = try explorer.write(newContents: "v2\n", to: file.path)
        let receipt2 = try explorer.write(newContents: "v3\n", to: file.path)

        let backup1 = try XCTUnwrap(receipt1.backupPath)
        let backup2 = try XCTUnwrap(receipt2.backupPath)
        XCTAssertNotEqual(backup1, backup2)
        XCTAssertEqual(try String(contentsOfFile: backup1, encoding: .utf8), "v1\n")
        XCTAssertEqual(try String(contentsOfFile: backup2, encoding: .utf8), "v2\n")
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "v3\n")

        // Every backup taken so far must still be recoverable — a second
        // write must never clobber the first backup.
        let backupDirEntries = try FileManager.default.contentsOfDirectory(atPath: backupDir.path)
        XCTAssertEqual(backupDirEntries.count, 2)
    }

    func testWriteRejectsPathOutsideConfiguredRoots() throws {
        let outsidePath = tempDir.appendingPathComponent("elsewhere/not-allowed.conf").path

        XCTAssertThrowsError(try explorer.write(newContents: "x", to: outsidePath)) { error in
            guard case ConfigFileExplorerError.pathOutsideAllowedRoots(let path) = error else {
                return XCTFail("expected pathOutsideAllowedRoots, got \(error)")
            }
            XCTAssertEqual(path, outsidePath)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: outsidePath))
    }

    func testWriteWithinHomeDirectoryIsAllowed() throws {
        let file = homeDir.appendingPathComponent(".config/tool/settings.toml")
        try TestSupport.makeFile(at: file, contents: "x = 1")

        XCTAssertNoThrow(try explorer.write(newContents: "x = 2", to: file.path))
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "x = 2")
    }

    // MARK: - Diffing

    func testPreviewDiffComparesCurrentContentsAgainstProposedContents() throws {
        let file = etcDir.appendingPathComponent("hosts")
        try TestSupport.makeFile(at: file, contents: "127.0.0.1 localhost")

        let changes = explorer.previewDiff(newContents: "127.0.0.1 localhost\n::1 localhost", to: file.path)

        XCTAssertEqual(changes, [
            LineDiff.Change(kind: .unchanged, text: "127.0.0.1 localhost"),
            LineDiff.Change(kind: .insertion, text: "::1 localhost")
        ])
    }

    func testPreviewDiffAgainstNonexistentFileTreatsCurrentContentsAsEmpty() {
        let file = etcDir.appendingPathComponent("doesnotexist.conf")
        let changes = explorer.previewDiff(newContents: "line1", to: file.path)
        XCTAssertEqual(changes, [LineDiff.Change(kind: .insertion, text: "line1")])
    }
}
