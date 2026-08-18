import XCTest
import CoreScanEngine
@testable import DevToolsDetectors

final class HomebrewDetectorTests: XCTestCase {
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

    func testFindsDownloadCacheEntries() async throws {
        fm.makeFile(home + "/Library/Caches/Homebrew/wget-1.24.5.tar.gz")
        fm.makeFile(home + "/Library/Caches/Homebrew/downloads/some-cask.dmg")

        let items = try await HomebrewDetector().scan(context: scanContext(roots: [home]))

        let paths = Set(items.filter { $0.sourceDetectorID == "dev.homebrew.download-cache" }.map(\.path))
        XCTAssertEqual(paths, [
            home + "/Library/Caches/Homebrew/downloads",
            home + "/Library/Caches/Homebrew/wget-1.24.5.tar.gz"
        ])
    }

    func testReturnsNoItemsWhenCacheDirMissing() async throws {
        let items = try await HomebrewDetector().scan(context: scanContext(roots: [home]))
        XCTAssertTrue(items.isEmpty)
    }

    func testGuidedActionsAreDescriptiveOnlyAndNeverExecuted() {
        let actions = HomebrewDetector.guidedActions
        XCTAssertTrue(actions.contains { $0.command == "brew cleanup" })
        XCTAssertTrue(actions.contains { $0.command == "brew autoremove" })
        for action in actions {
            XCTAssertFalse(action.explanation.isEmpty)
            XCTAssertTrue(action.explanation.contains("never run automatically") || action.explanation.contains("only suggests"))
        }
    }
}
