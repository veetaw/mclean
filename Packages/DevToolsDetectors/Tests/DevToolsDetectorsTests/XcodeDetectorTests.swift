import XCTest
import CoreScanEngine
@testable import DevToolsDetectors

final class XcodeDetectorTests: XCTestCase {
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

    private func makeDetector() -> XcodeDetector {
        XcodeDetector(
            staleDerivedDataThreshold: 30 * 24 * 3600,
            staleArchiveThreshold: 180 * 24 * 3600,
            staleDeviceSupportThreshold: 180 * 24 * 3600,
            now: { testReferenceDate }
        )
    }

    func testFindsDerivedDataPerProject() async throws {
        fm.makeFile(home + "/Library/Developer/Xcode/DerivedData/MyApp-abcdef/Build/Products/marker")

        let items = try await makeDetector().scan(context: scanContext(roots: [home]))

        XCTAssertTrue(items.contains {
            $0.sourceDetectorID == "dev.xcode.derived-data" &&
            $0.path == home + "/Library/Developer/Xcode/DerivedData/MyApp-abcdef"
        })
    }

    func testFlagsOldArchiveButNotRecentOne() async throws {
        let oldArchive = home + "/Library/Developer/Xcode/Archives/2024-01-01/MyApp 1-1-24, 1.00 AM.xcarchive"
        let recentArchive = home + "/Library/Developer/Xcode/Archives/2025-01-01/MyApp 1-1-25, 1.00 AM.xcarchive"
        fm.makeFile(oldArchive + "/Info.plist")
        fm.setModificationDate(daysAgo(400), at: oldArchive)
        fm.makeFile(recentArchive + "/Info.plist")
        fm.setModificationDate(daysAgo(2), at: recentArchive)

        let items = try await makeDetector().scan(context: scanContext(roots: [home]))

        let archivePaths = Set(items.filter { $0.sourceDetectorID == "dev.xcode.old-archive" }.map(\.path))
        XCTAssertEqual(archivePaths, [oldArchive])
    }

    func testFindsSimulatorRuntimes() async throws {
        fm.makeFile(home + "/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 17.simruntime/Info.plist")

        let items = try await makeDetector().scan(context: scanContext(roots: [home]))

        XCTAssertTrue(items.contains { $0.sourceDetectorID == "dev.xcode.simulator-runtime" })
    }

    func testFlagsOldDeviceSupportButNotRecentOne() async throws {
        let old = home + "/Library/Developer/Xcode/iOS DeviceSupport/16.0 (20A123)"
        let recent = home + "/Library/Developer/Xcode/iOS DeviceSupport/18.0 (22A123)"
        fm.makeFile(old + "/Symbols/marker")
        fm.setModificationDate(daysAgo(400), at: old)
        fm.makeFile(recent + "/Symbols/marker")
        fm.setModificationDate(daysAgo(1), at: recent)

        let items = try await makeDetector().scan(context: scanContext(roots: [home]))

        let flagged = Set(items.filter { $0.sourceDetectorID == "dev.xcode.device-support" }.map(\.path))
        XCTAssertEqual(flagged, [old])
    }
}
