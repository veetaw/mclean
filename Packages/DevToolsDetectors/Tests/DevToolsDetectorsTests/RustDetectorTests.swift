import XCTest
import CoreScanEngine
@testable import DevToolsDetectors

final class RustDetectorTests: XCTestCase {
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

    private func makeDetector(thresholdDays: Double = 30) -> RustDetector {
        RustDetector(staleTargetThreshold: thresholdDays * 24 * 3600, now: { testReferenceDate })
    }

    func testFindsCargoRegistrySubdirectories() async throws {
        fm.makeFile(home + "/.cargo/registry/cache/index.crates.io/foo.crate")
        fm.makeFile(home + "/.cargo/registry/src/index.crates.io/foo/lib.rs")
        fm.makeFile(home + "/.cargo/registry/index/index.crates.io/config.json")

        let items = try await makeDetector().scan(context: scanContext(roots: [home]))

        XCTAssertTrue(items.contains { $0.sourceDetectorID == "dev.rust.cargo-registry-cache" })
        XCTAssertTrue(items.contains { $0.sourceDetectorID == "dev.rust.cargo-registry-src" })
        XCTAssertTrue(items.contains { $0.sourceDetectorID == "dev.rust.cargo-registry-index" })
    }

    func testStaleTargetDirIsFlaggedUsingManifestMTime() async throws {
        let project = home + "/projects/old-crate"
        fm.makeFile(project + "/Cargo.toml")
        fm.setModificationDate(daysAgo(60), at: project + "/Cargo.toml")
        fm.makeFile(project + "/target/debug/build/marker")

        let items = try await makeDetector().scan(context: scanContext(roots: [home]))

        let target = items.first { $0.sourceDetectorID == "dev.rust.stale-target-dir" }
        XCTAssertNotNil(target)
        XCTAssertEqual(target?.path, project + "/target")
        XCTAssertEqual(target?.lastUsed?.source, .manifestOrLockfileMTime)
    }

    func testFreshTargetDirIsNotFlagged() async throws {
        let project = home + "/projects/active-crate"
        fm.makeFile(project + "/Cargo.toml")
        fm.setModificationDate(daysAgo(1), at: project + "/Cargo.toml")
        fm.makeFile(project + "/target/debug/build/marker")

        let items = try await makeDetector().scan(context: scanContext(roots: [home]))

        XCTAssertFalse(items.contains { $0.path == project + "/target" })
    }

    func testTargetDirWithoutSiblingCargoTomlIsIgnored() async throws {
        fm.makeFile(home + "/random/target/some-file")

        let items = try await makeDetector().scan(context: scanContext(roots: [home]))

        XCTAssertFalse(items.contains { $0.sourceDetectorID == "dev.rust.stale-target-dir" })
    }
}
