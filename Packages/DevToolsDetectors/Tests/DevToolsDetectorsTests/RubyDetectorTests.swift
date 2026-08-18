import XCTest
import CoreScanEngine
@testable import DevToolsDetectors

final class RubyDetectorTests: XCTestCase {
    var home: String!
    let fm = FileManager.default

    override func setUp() {
        super.setUp()
        home = TempHome.make()
    }

    override func tearDown() {
        TempHome.cleanup(home)
        home = nil
        super.tearDown()
    }

    private func makeDetector(thresholdDays: Double = 180) -> RubyDetector {
        RubyDetector(staleVersionThreshold: thresholdDays * 24 * 3600, now: { testReferenceDate })
    }

    func testFindsGemHomeCache() async throws {
        fm.makeFile(home + "/.gem/specs/foo.gemspec")

        let items = try await makeDetector().scan(context: scanContext(roots: [home]))

        XCTAssertTrue(items.contains { $0.sourceDetectorID == "dev.ruby.gem-home-cache" })
    }

    func testFindsPerVersionGemCache() async throws {
        fm.makeFile(home + "/.rbenv/versions/3.2.0/lib/ruby/gems/3.2.0/cache/foo-1.0.gem")

        let items = try await makeDetector().scan(context: scanContext(roots: [home]))

        XCTAssertTrue(items.contains { $0.sourceDetectorID == "dev.ruby.gem-version-cache" })
    }

    func testFlagsStaleNonGlobalRbenvVersionButNotGlobalOne() async throws {
        fm.makeFile(home + "/.rbenv/version", contents: "3.2.0")
        fm.makeDir(home + "/.rbenv/versions/3.2.0")
        fm.setModificationDate(daysAgo(400), at: home + "/.rbenv/versions/3.2.0")
        fm.makeDir(home + "/.rbenv/versions/3.1.0")
        fm.setModificationDate(daysAgo(400), at: home + "/.rbenv/versions/3.1.0")

        let items = try await makeDetector().scan(context: scanContext(roots: [home]))

        let flaggedPaths = Set(items.filter { $0.sourceDetectorID == "dev.ruby.unused-rbenv-version" }.map(\.path))
        XCTAssertEqual(flaggedPaths, [home + "/.rbenv/versions/3.1.0"])
    }

    func testDoesNotFlagRecentlyUsedNonGlobalVersion() async throws {
        fm.makeFile(home + "/.rbenv/version", contents: "3.2.0")
        fm.makeDir(home + "/.rbenv/versions/3.2.0")
        fm.setModificationDate(daysAgo(400), at: home + "/.rbenv/versions/3.2.0")
        fm.makeDir(home + "/.rbenv/versions/3.1.0")
        fm.setModificationDate(daysAgo(2), at: home + "/.rbenv/versions/3.1.0")

        let items = try await makeDetector().scan(context: scanContext(roots: [home]))

        XCTAssertFalse(items.contains { $0.sourceDetectorID == "dev.ruby.unused-rbenv-version" })
    }
}
