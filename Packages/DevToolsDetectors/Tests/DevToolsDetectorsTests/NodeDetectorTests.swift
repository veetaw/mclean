import XCTest
import CoreScanEngine
@testable import DevToolsDetectors

final class NodeDetectorTests: XCTestCase {
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

    private func makeDetector(thresholdDays: Double = 90) -> NodeDetector {
        NodeDetector(staleNodeModulesThreshold: thresholdDays * 24 * 3600, now: { testReferenceDate })
    }

    func testStaleNodeModulesIsFlaggedUsingLockfileMTime() async throws {
        let project = home + "/projects/old-app"
        fm.makeFile(project + "/package-lock.json")
        fm.setModificationDate(daysAgo(200), at: project + "/package-lock.json")
        fm.makeFile(project + "/node_modules/left-pad/index.js")

        let items = try await makeDetector().scan(context: scanContext(roots: [home]))

        let stale = items.first { $0.sourceDetectorID == "dev.node.stale-node-modules" }
        XCTAssertNotNil(stale)
        XCTAssertEqual(stale?.path, project + "/node_modules")
        XCTAssertEqual(stale?.lastUsed?.source, .manifestOrLockfileMTime)
    }

    func testFreshNodeModulesIsNotFlagged() async throws {
        let project = home + "/projects/active-app"
        fm.makeFile(project + "/package-lock.json")
        fm.setModificationDate(daysAgo(1), at: project + "/package-lock.json")
        fm.makeFile(project + "/node_modules/left-pad/index.js")

        let items = try await makeDetector().scan(context: scanContext(roots: [home]))

        XCTAssertFalse(items.contains { $0.path == project + "/node_modules" })
    }

    func testStaleNodeModulesWithActiveGitRepoNotesButDoesNotSuppress() async throws {
        let project = home + "/projects/dirty-repo-app"
        fm.makeDir(project + "/.git")
        fm.makeFile(project + "/package-lock.json")
        fm.setModificationDate(daysAgo(200), at: project + "/package-lock.json")
        fm.makeFile(project + "/node_modules/left-pad/index.js")

        let items = try await makeDetector().scan(context: scanContext(roots: [home]))

        let stale = items.first { $0.sourceDetectorID == "dev.node.stale-node-modules" }
        XCTAssertNotNil(stale)
        XCTAssertTrue(stale?.reason.contains("git repository") ?? false)
        XCTAssertTrue(stale?.reason.contains("does not check") ?? false)
    }

    func testFindsPackageManagerCaches() async throws {
        fm.makeFile(home + "/.npm/_cacache/index.json")
        fm.makeFile(home + "/Library/Caches/Yarn/v6/foo")
        fm.makeFile(home + "/Library/pnpm/store/v3/foo")

        let items = try await makeDetector().scan(context: scanContext(roots: [home]))

        XCTAssertTrue(items.contains { $0.sourceDetectorID == "dev.node.npm-cache" })
        XCTAssertTrue(items.contains { $0.sourceDetectorID == "dev.node.yarn-cache" })
        XCTAssertTrue(items.contains { $0.sourceDetectorID == "dev.node.pnpm-store" })
    }

    func testFindsTurborepoAndBundlerCaches() async throws {
        let project = home + "/projects/monorepo"
        fm.makeFile(project + "/.turbo/cache/abc.tar")
        fm.makeFile(project + "/node_modules/.cache/webpack/abc.pack")

        let items = try await makeDetector().scan(context: scanContext(roots: [home]))

        XCTAssertTrue(items.contains { $0.sourceDetectorID == "dev.node.turborepo-cache" && $0.path == project + "/.turbo" })
        XCTAssertTrue(items.contains { $0.sourceDetectorID == "dev.node.bundler-cache" && $0.path == project + "/node_modules/.cache" })
    }
}
