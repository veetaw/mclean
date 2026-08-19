import XCTest
@testable import PowerUserInspectors

/// Feeds each parser captured sample output from the real CLI tool, so
/// these tests never require pip/npm/cargo/gem/go/brew to actually be
/// installed on the machine running them.
final class PackageListParsersTests: XCTestCase {
    // MARK: - pip

    func testParsePipListDecodesNameAndVersion() {
        let sample = """
        [
          {"name": "pip", "version": "23.3.1"},
          {"name": "requests", "version": "2.31.0"}
        ]
        """
        let entries = PackageListParsers.parsePipList(json: sample)
        XCTAssertEqual(entries.map(\.name), ["pip", "requests"])
        XCTAssertEqual(entries.map(\.version), ["23.3.1", "2.31.0"])
        XCTAssertTrue(entries.allSatisfy { $0.ecosystem == .pip })
    }

    func testParsePipListOnGarbageReturnsEmpty() {
        XCTAssertEqual(PackageListParsers.parsePipList(json: "not json"), [])
        XCTAssertEqual(PackageListParsers.parsePipList(json: ""), [])
    }

    // MARK: - npm

    func testParseNpmGlobalListDecodesDependencies() {
        let sample = """
        {
          "name": "global-root",
          "dependencies": {
            "npm": {"version": "10.2.4"},
            "typescript": {"version": "5.3.3"}
          }
        }
        """
        let entries = PackageListParsers.parseNpmGlobalList(json: sample)
        XCTAssertEqual(entries.map(\.name), ["npm", "typescript"])
        XCTAssertEqual(entries.first { $0.name == "typescript" }?.version, "5.3.3")
        XCTAssertTrue(entries.allSatisfy { $0.ecosystem == .npm })
    }

    func testParseNpmGlobalListWithNoDependenciesReturnsEmpty() {
        XCTAssertEqual(PackageListParsers.parseNpmGlobalList(json: "{\"name\": \"root\"}"), [])
        XCTAssertEqual(PackageListParsers.parseNpmGlobalList(json: "garbage"), [])
    }

    // MARK: - cargo

    func testParseCargoInstallListSkipsIndentedBinaryLines() {
        let sample = """
        bat v0.24.0:
            bat
        cargo-edit v0.12.2:
            cargo-add
            cargo-rm
        ripgrep v14.1.0 (https://github.com/BurntSushi/ripgrep):
            rg
        """
        let entries = PackageListParsers.parseCargoInstallList(text: sample)
        XCTAssertEqual(entries.map(\.name), ["bat", "cargo-edit", "ripgrep"])
        XCTAssertEqual(entries.map(\.version), ["0.24.0", "0.12.2", "14.1.0"])
        XCTAssertTrue(entries.allSatisfy { $0.ecosystem == .cargo })
    }

    func testParseCargoInstallListOnEmptyOutputReturnsEmpty() {
        XCTAssertEqual(PackageListParsers.parseCargoInstallList(text: ""), [])
    }

    // MARK: - gem

    func testParseGemListExpandsMultipleVersionsAndStripsDefaultMarker() {
        let sample = """
        bigdecimal (default: 3.1.4)
        bundler (2.4.10, 2.3.7)
        did_you_mean (default: 1.6.3)
        """
        let entries = PackageListParsers.parseGemList(text: sample)
        XCTAssertEqual(entries.filter { $0.name == "bigdecimal" }.map(\.version), ["3.1.4"])
        XCTAssertEqual(entries.filter { $0.name == "bundler" }.map(\.version), ["2.4.10", "2.3.7"])
        XCTAssertTrue(entries.allSatisfy { $0.ecosystem == .gem })
    }

    func testParseGemListOnEmptyOutputReturnsEmpty() {
        XCTAssertEqual(PackageListParsers.parseGemList(text: ""), [])
    }

    // MARK: - go modules

    func testParseGoListModulesSkipsMainModuleAndKeepsDependencies() {
        let sample = """
        github.com/me/myproject
        github.com/pkg/errors v0.9.1
        golang.org/x/text v0.14.0
        """
        let entries = PackageListParsers.parseGoListModules(text: sample)
        XCTAssertEqual(entries.map(\.name), ["github.com/pkg/errors", "golang.org/x/text"])
        XCTAssertEqual(entries.map(\.version), ["v0.9.1", "v0.14.0"])
        XCTAssertTrue(entries.allSatisfy { $0.ecosystem == .goModules })
    }

    func testParseGoListModulesWithOnlyMainModuleReturnsEmpty() {
        XCTAssertEqual(PackageListParsers.parseGoListModules(text: "github.com/me/myproject"), [])
    }

    // MARK: - brew

    func testParseBrewListVersionsExpandsMultipleInstalledVersions() {
        let sample = """
        git 2.43.0
        node 20.10.0 18.19.0
        wget 1.21.4
        """
        let entries = PackageListParsers.parseBrewListVersions(text: sample)
        XCTAssertEqual(entries.filter { $0.name == "git" }.map(\.version), ["2.43.0"])
        XCTAssertEqual(entries.filter { $0.name == "node" }.map(\.version), ["20.10.0", "18.19.0"])
        XCTAssertTrue(entries.allSatisfy { $0.ecosystem == .homebrew })
    }

    func testParseBrewListVersionsOnEmptyOutputReturnsEmpty() {
        XCTAssertEqual(PackageListParsers.parseBrewListVersions(text: ""), [])
    }
}
