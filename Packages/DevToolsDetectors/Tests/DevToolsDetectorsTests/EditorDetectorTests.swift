import XCTest
import CoreScanEngine
@testable import DevToolsDetectors

final class EditorDetectorTests: XCTestCase {
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

    private func makeDetector(thresholdDays: Double = 180) -> EditorDetector {
        EditorDetector(staleExtensionThreshold: thresholdDays * 24 * 3600, now: { testReferenceDate })
    }

    func testFindsJetBrainsCache() async throws {
        fm.makeFile(home + "/Library/Caches/JetBrains/IntelliJIdea2024.1/caches/marker")

        let items = try await makeDetector().scan(context: scanContext(roots: [home]))

        XCTAssertTrue(items.contains { $0.sourceDetectorID == "dev.editors.jetbrains-cache" })
    }

    func testFindsVSCodeCacheDirectoriesByPrefix() async throws {
        fm.makeFile(home + "/Library/Application Support/Code/Cache/data_0/marker")
        fm.makeFile(home + "/Library/Application Support/Code/CachedData/1.85.0/marker")
        fm.makeFile(home + "/Library/Application Support/Code/User/settings.json") // not a cache dir

        let items = try await makeDetector().scan(context: scanContext(roots: [home]))

        let vscodeCachePaths = Set(items.filter { $0.sourceDetectorID == "dev.editors.vscode-cache" }.map(\.path))
        XCTAssertEqual(vscodeCachePaths, [
            home + "/Library/Application Support/Code/Cache",
            home + "/Library/Application Support/Code/CachedData"
        ])
    }

    func testFlagsStaleExtensionButNotRecentOne() async throws {
        let old = home + "/.vscode/extensions/old.extension-1.0.0"
        let recent = home + "/.vscode/extensions/recent.extension-2.0.0"
        fm.makeFile(old + "/package.json")
        fm.setModificationDate(daysAgo(400), at: old)
        fm.makeFile(recent + "/package.json")
        fm.setModificationDate(daysAgo(1), at: recent)

        let items = try await makeDetector().scan(context: scanContext(roots: [home]))

        let flagged = Set(items.filter { $0.sourceDetectorID == "dev.editors.vscode-unused-extension" }.map(\.path))
        XCTAssertEqual(flagged, [old])
    }
}
