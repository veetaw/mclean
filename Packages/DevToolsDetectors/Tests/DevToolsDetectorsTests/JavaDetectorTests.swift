import XCTest
import CoreScanEngine
@testable import DevToolsDetectors

final class JavaDetectorTests: XCTestCase {
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

    private func makeDetector(thresholdDays: Double = 180) -> JavaDetector {
        JavaDetector(staleCandidateThreshold: thresholdDays * 24 * 3600, now: { testReferenceDate })
    }

    func testFindsGradleAndMavenCaches() async throws {
        fm.makeFile(home + "/.gradle/caches/modules-2/foo.jar")
        fm.makeFile(home + "/.m2/repository/com/foo/foo-1.0.jar")

        let items = try await makeDetector().scan(context: scanContext(roots: [home]))

        XCTAssertTrue(items.contains { $0.sourceDetectorID == "dev.java.gradle-cache" })
        XCTAssertTrue(items.contains { $0.sourceDetectorID == "dev.java.maven-cache" })
    }

    func testFlagsStaleNonCurrentSdkmanCandidateOnly() async throws {
        let candidateDir = home + "/.sdkman/candidates/java"
        fm.makeDir(candidateDir + "/21.0.1-tem")
        fm.makeDir(candidateDir + "/17.0.1-tem")
        fm.setModificationDate(daysAgo(400), at: candidateDir + "/17.0.1-tem")
        fm.setModificationDate(daysAgo(400), at: candidateDir + "/21.0.1-tem")
        fm.makeSymlink(at: candidateDir + "/current", to: candidateDir + "/21.0.1-tem")

        let items = try await makeDetector().scan(context: scanContext(roots: [home]))

        let flagged = Set(items.filter { $0.sourceDetectorID == "dev.java.sdkman-unused-candidate" }.map(\.path))
        XCTAssertEqual(flagged, [candidateDir + "/17.0.1-tem"])
    }

    func testDoesNotFlagFreshCandidates() async throws {
        let candidateDir = home + "/.sdkman/candidates/java"
        fm.makeDir(candidateDir + "/21.0.1-tem")
        fm.makeDir(candidateDir + "/17.0.1-tem")
        fm.setModificationDate(daysAgo(2), at: candidateDir + "/17.0.1-tem")
        fm.makeSymlink(at: candidateDir + "/current", to: candidateDir + "/21.0.1-tem")

        let items = try await makeDetector().scan(context: scanContext(roots: [home]))

        XCTAssertFalse(items.contains { $0.sourceDetectorID == "dev.java.sdkman-unused-candidate" })
    }
}
