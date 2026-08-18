import XCTest
import CoreScanEngine
@testable import DevToolsDetectors

final class GoDetectorTests: XCTestCase {
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

    func testFindsDefaultModuleAndBuildCache() async throws {
        fm.makeFile(home + "/go/pkg/mod/github.com/foo/bar@v1.0.0/go.mod")
        fm.makeFile(home + "/Library/Caches/go-build/ab/abcdef")

        let items = try await GoDetector(environment: [:]).scan(context: scanContext(roots: [home]))

        XCTAssertTrue(items.contains { $0.sourceDetectorID == "dev.go.module-cache" && $0.path == home + "/go/pkg/mod" })
        XCTAssertTrue(items.contains { $0.sourceDetectorID == "dev.go.build-cache" && $0.path == home + "/Library/Caches/go-build" })
    }

    func testRespectsGOPATHAndGOCACHEEnvironmentOverrides() async throws {
        let customGopath = home + "/custom-gopath"
        let customGocache = home + "/custom-gocache"
        fm.makeFile(customGopath + "/pkg/mod/github.com/foo/bar@v1.0.0/go.mod")
        fm.makeFile(customGocache + "/ab/abcdef")

        let detector = GoDetector(environment: ["GOPATH": customGopath, "GOCACHE": customGocache])
        let items = try await detector.scan(context: scanContext(roots: [home]))

        XCTAssertTrue(items.contains { $0.path == customGopath + "/pkg/mod" })
        XCTAssertTrue(items.contains { $0.path == customGocache })
        // The default paths should NOT be reported since they don't exist.
        XCTAssertFalse(items.contains { $0.path == home + "/go/pkg/mod" })
    }

    func testReturnsNoItemsWhenNothingPresent() async throws {
        let items = try await GoDetector(environment: [:]).scan(context: scanContext(roots: [home]))
        XCTAssertTrue(items.isEmpty)
    }
}
