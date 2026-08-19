import XCTest
@testable import Optimization

final class LaunchAgentPlistParserTests: TempDirTestCase {
    func testParsesValidPlistWithRunAtLoadTrue() throws {
        let url = tempDir.appendingPathComponent("com.example.runatload.plist")
        try TestSupport.makeLaunchAgentPlist(
            at: url,
            label: "com.example.runatload",
            program: "/usr/local/bin/agent-one",
            runAtLoad: true
        )

        let parsed = LaunchAgentPlistParser.parse(contentsOfFile: url.path, scope: .user)

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.label, "com.example.runatload")
        XCTAssertEqual(parsed?.program, "/usr/local/bin/agent-one")
        XCTAssertEqual(parsed?.runAtLoad, true)
        XCTAssertEqual(parsed?.keepAlive, false)
        XCTAssertEqual(parsed?.scope, .user)
        XCTAssertEqual(parsed?.path, url.path)
    }

    func testParsesValidPlistWithoutRunAtLoad() throws {
        let url = tempDir.appendingPathComponent("com.example.norunatload.plist")
        try TestSupport.makeLaunchAgentPlist(
            at: url,
            label: "com.example.norunatload",
            program: "/usr/local/bin/agent-two",
            runAtLoad: false,
            keepAlive: true
        )

        let parsed = LaunchAgentPlistParser.parse(contentsOfFile: url.path, scope: .system)

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.runAtLoad, false)
        XCTAssertEqual(parsed?.keepAlive, true)
        XCTAssertEqual(parsed?.scope, .system)
    }

    func testMalformedPlistReturnsNilRatherThanThrowing() throws {
        let url = tempDir.appendingPathComponent("com.example.malformed.plist")
        try TestSupport.makeMalformedPlist(at: url)

        let parsed = LaunchAgentPlistParser.parse(contentsOfFile: url.path, scope: .user)

        XCTAssertNil(parsed)
    }

    func testMissingFileReturnsNil() {
        let parsed = LaunchAgentPlistParser.parse(
            contentsOfFile: tempDir.appendingPathComponent("does-not-exist.plist").path,
            scope: .user
        )
        XCTAssertNil(parsed)
    }

    func testPlistMissingLabelStillParsesWithNilLabel() throws {
        let url = tempDir.appendingPathComponent("com.example.nolabel.plist")
        try TestSupport.makeLaunchAgentPlist(at: url, label: nil, runAtLoad: true)

        let parsed = LaunchAgentPlistParser.parse(contentsOfFile: url.path, scope: .user)

        XCTAssertNotNil(parsed)
        XCTAssertNil(parsed?.label)
        XCTAssertEqual(parsed?.runAtLoad, true)
    }

    func testDiscoverPlistPathsFindsOnlyPlistFilesNonRecursively() throws {
        try TestSupport.makeLaunchAgentPlist(
            at: tempDir.appendingPathComponent("a.plist"),
            label: "a",
            runAtLoad: true
        )
        try TestSupport.makeLaunchAgentPlist(
            at: tempDir.appendingPathComponent("b.plist"),
            label: "b",
            runAtLoad: false
        )
        try "not a plist".write(
            to: tempDir.appendingPathComponent("readme.txt"),
            atomically: true,
            encoding: .utf8
        )
        try TestSupport.makeDirectory(at: tempDir.appendingPathComponent("nested"))
        try TestSupport.makeLaunchAgentPlist(
            at: tempDir.appendingPathComponent("nested/c.plist"),
            label: "c",
            runAtLoad: true
        )

        let paths = LaunchAgentPlistParser.discoverPlistPaths(in: tempDir.path)

        XCTAssertEqual(paths.map { URL(fileURLWithPath: $0).lastPathComponent }, ["a.plist", "b.plist"])
    }

    func testDiscoverPlistPathsReturnsEmptyForMissingDirectory() {
        let paths = LaunchAgentPlistParser.discoverPlistPaths(
            in: tempDir.appendingPathComponent("does-not-exist").path
        )
        XCTAssertTrue(paths.isEmpty)
    }

    func testDiscoverAndParseSkipsMalformedFilesWithoutThrowing() throws {
        try TestSupport.makeLaunchAgentPlist(
            at: tempDir.appendingPathComponent("good.plist"),
            label: "com.example.good",
            runAtLoad: true
        )
        try TestSupport.makeMalformedPlist(at: tempDir.appendingPathComponent("bad.plist"))

        let parsed = LaunchAgentPlistParser.discoverAndParse(in: tempDir.path, scope: .user)

        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed.first?.label, "com.example.good")
    }
}
