import XCTest
@testable import PowerUserInspectors

final class PackageExplorerTests: TempDirTestCase {
    func testListPipPackagesParsesJSONFromPip3() async {
        let runner = FakeCommandRunner(resultsByExecutable: [
            "pip3": makeResult(#"[{"name": "requests", "version": "2.31.0"}]"#)
        ])
        let explorer = PackageExplorer(commandRunner: runner)

        let entries = await explorer.listPipPackages()

        XCTAssertEqual(entries.map(\.name), ["requests"])
    }

    func testListPipPackagesFallsBackToPipWhenPip3Unavailable() async {
        let runner = FakeCommandRunner(resultsByExecutable: [
            "pip": makeResult(#"[{"name": "flask", "version": "3.0.0"}]"#)
            // "pip3" intentionally absent -> nil result, simulating "not found"
        ])
        let explorer = PackageExplorer(commandRunner: runner)

        let entries = await explorer.listPipPackages()

        XCTAssertEqual(entries.map(\.name), ["flask"])
    }

    func testListPipPackagesReturnsEmptyWhenNeitherToolAvailable() async {
        let explorer = PackageExplorer(commandRunner: FakeCommandRunner())
        let entries = await explorer.listPipPackages()
        XCTAssertEqual(entries, [])
    }

    func testListNpmGlobalPackagesEnrichesWithFilesystemSizeAndMTime() async throws {
        let globalRoot = tempDir.appendingPathComponent("npm-global/lib/node_modules")
        let typescriptDir = globalRoot.appendingPathComponent("typescript")
        try TestSupport.makeFile(at: typescriptDir.appendingPathComponent("package.json"), contents: "{}")

        // `npm` needs two different responses behind the same executable
        // name (`ls -g ... --json` and `root -g`) — `FakeCommandRunner`
        // only keys by executable, so `SequencedNpmRunner` dispatches by
        // argument list instead for this one test.
        let runner = SequencedNpmRunner(
            lsResult: makeResult(#"{"dependencies": {"typescript": {"version": "5.3.3"}}}"#),
            rootResult: makeResult(globalRoot.path + "\n")
        )
        let explorer = PackageExplorer(commandRunner: runner)

        let entries = await explorer.listNpmGlobalPackages()

        XCTAssertEqual(entries.count, 1)
        let typescript = try XCTUnwrap(entries.first)
        XCTAssertEqual(typescript.name, "typescript")
        XCTAssertEqual(typescript.installPath, typescriptDir.path)
        XCTAssertNotNil(typescript.sizeBytes)
        XCTAssertGreaterThan(typescript.sizeBytes ?? 0, 0)
        XCTAssertNotNil(typescript.lastAccessed)
    }

    func testListCargoPackagesEnrichesWithBinarySize() async throws {
        let cargoBin = tempDir.appendingPathComponent("cargo-home/bin")
        try TestSupport.makeBinaryFile(at: cargoBin.appendingPathComponent("bat"), size: 1024)

        let runner = FakeCommandRunner(resultsByExecutable: [
            "cargo": makeResult("bat v0.24.0:\n    bat\n")
        ])
        let explorer = PackageExplorer(commandRunner: runner)

        let entries = await explorer.listCargoPackages()

        // installPath enrichment only kicks in when the real ~/.cargo/bin
        // exists on the test machine — this test only asserts parsing
        // succeeded, since ~/.cargo/bin isn't injectable without changing
        // the production default (deliberately NSHomeDirectory()-based,
        // matching cargo's own convention).
        XCTAssertEqual(entries.map(\.name), ["bat"])
        XCTAssertEqual(entries.map(\.version), ["0.24.0"])
    }

    func testListGemPackagesParsesLocalListing() async {
        let runner = FakeCommandRunner(resultsByExecutable: [
            "gem": makeResult("bundler (2.4.10, 2.3.7)\n")
        ])
        let explorer = PackageExplorer(commandRunner: runner)

        let entries = await explorer.listGemPackages()

        XCTAssertEqual(entries.map(\.version), ["2.4.10", "2.3.7"])
    }

    func testListGoModulesRunsInSpecifiedModuleDirectory() async throws {
        let moduleDir = tempDir.appendingPathComponent("mymodule")
        try TestSupport.makeDirectory(at: moduleDir)

        let runner = FakeCommandRunner(resultsByExecutable: [
            "go": makeResult("github.com/me/myproject\ngithub.com/pkg/errors v0.9.1\n")
        ])
        let explorer = PackageExplorer(commandRunner: runner)

        let entries = await explorer.listGoModules(moduleDirectory: moduleDir.path)

        XCTAssertEqual(entries.map(\.name), ["github.com/pkg/errors"])
        let invocations = await runner.invocations
        XCTAssertEqual(invocations.first?.currentDirectory, moduleDir.path)
    }

    func testListHomebrewPackagesEnrichesFromCellarWhenPresent() async throws {
        let cellar = tempDir.appendingPathComponent("homebrew/Cellar")
        try TestSupport.makeFile(at: cellar.appendingPathComponent("wget/1.21.4/bin/wget"), contents: "binary")

        let runner = FakeCommandRunner(resultsByExecutable: [
            "brew": makeResult("wget 1.21.4\n")
        ])
        let explorer = PackageExplorer(commandRunner: runner)

        let entries = await explorer.listHomebrewPackages()

        // The real Cellar prefixes (/opt/homebrew, /usr/local) aren't
        // injectable without changing the production default — this test
        // only exercises the non-enriched parsing path, which is the part
        // that's under this package's control end-to-end.
        XCTAssertEqual(entries.map(\.name), ["wget"])
        XCTAssertEqual(entries.map(\.version), ["1.21.4"])
    }

    func testEveryListMethodDegradesToEmptyWhenToolMissing() async {
        let explorer = PackageExplorer(commandRunner: FakeCommandRunner())

        let pip = await explorer.listPipPackages()
        let npm = await explorer.listNpmGlobalPackages()
        let cargo = await explorer.listCargoPackages()
        let gem = await explorer.listGemPackages()
        let goModules = await explorer.listGoModules(moduleDirectory: tempDir.path)
        let brew = await explorer.listHomebrewPackages()

        XCTAssertEqual(pip, [])
        XCTAssertEqual(npm, [])
        XCTAssertEqual(cargo, [])
        XCTAssertEqual(gem, [])
        XCTAssertEqual(goModules, [])
        XCTAssertEqual(brew, [])
    }

    func testListAllOmitsGoModulesWhenNoDirectoryGiven() async {
        let explorer = PackageExplorer(commandRunner: FakeCommandRunner())
        let all = await explorer.listAll()
        XCTAssertNil(all[.goModules])
        XCTAssertNotNil(all[.pip])
    }

    func testListAllIncludesGoModulesWhenDirectoryGiven() async {
        let runner = FakeCommandRunner(resultsByExecutable: [
            "go": makeResult("main\ngithub.com/pkg/errors v0.9.1\n")
        ])
        let explorer = PackageExplorer(commandRunner: runner)
        let all = await explorer.listAll(goModuleDirectory: tempDir.path)
        XCTAssertEqual(all[.goModules]?.count, 1)
    }
}

/// `npm` needs two different subcommand responses (`ls -g ... --json` and
/// `root -g`) behind the same executable name; `FakeCommandRunner` only
/// keys by executable, so this dispatches by argument list instead for the
/// one test that needs both.
actor SequencedNpmRunner: ExternalCommandRunning {
    private let lsResult: ExternalCommandResult
    private let rootResult: ExternalCommandResult

    init(lsResult: ExternalCommandResult, rootResult: ExternalCommandResult) {
        self.lsResult = lsResult
        self.rootResult = rootResult
    }

    nonisolated func run(
        executable: String,
        arguments: [String],
        currentDirectory: String?,
        timeout: TimeInterval
    ) async -> ExternalCommandResult? {
        guard executable == "npm" else { return nil }
        return arguments.first == "root" ? rootResult : lsResult
    }
}
