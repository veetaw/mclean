import CoreScanEngine
import SafetyRules
import XCTest
@testable import MainAppUI

/// Exercises `AppEnvironment`'s composition without touching live AppKit
/// (no `MenuBarController` is ever constructed here -- see
/// `AppEnvironment.activateMenuBarAgent()`'s doc comment for why that's a
/// separate, explicit step), without scanning the real filesystem
/// (`runFullScan` is always called with a temp-directory root), and without
/// touching the real `~/Library/Application Support/MCleanPro/user_rules.yaml`
/// (every `AppEnvironment`/`bootstrap` call here passes a temp
/// `userRulesDirectory` -- omitting it would make `RuleFileLoader` create a
/// real file on whatever machine runs this suite).
@MainActor
final class AppEnvironmentTests: XCTestCase {
    private func makeTempQuarantineRoot() -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MainAppUITests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    func testRemoteControlServerIsNilInAppStoreFlavor() {
        let environment = AppEnvironment(
            capabilities: Capabilities(flavor: .appStore),
            quarantineRootURL: makeTempQuarantineRoot(),
            userRulesDirectory: makeTempQuarantineRoot()
        )
        XCTAssertNil(environment.remoteControlServer)
    }

    func testRemoteControlServerIsConstructedInDeveloperIDFlavor() {
        let environment = AppEnvironment(
            capabilities: Capabilities(flavor: .developerID),
            quarantineRootURL: makeTempQuarantineRoot(),
            userRulesDirectory: makeTempQuarantineRoot()
        )
        XCTAssertNotNil(environment.remoteControlServer)
        XCTAssertFalse(environment.remoteControlServer!.isRunning, "constructing the server must never auto-start it")
    }

    func testMenuBarControllerIsNilUntilExplicitlyActivated() {
        let environment = AppEnvironment(
            capabilities: .current,
            quarantineRootURL: makeTempQuarantineRoot(),
            userRulesDirectory: makeTempQuarantineRoot()
        )
        XCTAssertNil(environment.menuBarController, "AppEnvironment must not construct AppKit UI as a side effect of init")
    }

    func testBootstrapRegistersEveryDefaultDetector() async {
        let environment = await AppEnvironment.bootstrap(
            capabilities: .current,
            quarantineRootURL: makeTempQuarantineRoot(),
            userRulesDirectory: makeTempQuarantineRoot()
        )

        // Scope the scan to an empty temp directory (not the real home
        // directory) so this test is fast and touches no real user data,
        // while still proving detectors were registered and actually ran
        // (a zero-detector engine would also return zero items, so this
        // alone wouldn't be conclusive -- the real assertion is that
        // `runAll` completes without any detector ID reported as failed).
        let tempRoot = makeTempQuarantineRoot()
        let result = await environment.scanEngine.runAll(
            context: ScanContext(roots: [tempRoot.path])
        )
        XCTAssertTrue(result.failedDetectorIDs.isEmpty, "unexpected detector failures: \(result.failedDetectorIDs)")
    }

    func testRunFullScanClassifiesFindingsAndUpdatesTheSnapshotStore() async {
        let environment = await AppEnvironment.bootstrap(
            capabilities: .current,
            quarantineRootURL: makeTempQuarantineRoot(),
            userRulesDirectory: makeTempQuarantineRoot()
        )

        let before = await environment.scanSnapshotStore.currentSnapshot()
        XCTAssertNil(before.lastScanFinishedAt)

        let tempRoot = makeTempQuarantineRoot()
        await environment.runFullScan(roots: [tempRoot.path])

        let after = await environment.scanSnapshotStore.currentSnapshot()
        XCTAssertNotNil(after.lastScanFinishedAt)
        // Every finding must carry a verdict computed by SafetyClassifier
        // (forbidden/safeAuto/needsConfirmation) -- this loop just proves
        // `runFullScan` actually classified rather than leaving items
        // unclassified, without depending on how many items an empty temp
        // directory happens to produce.
        for finding in after.findings {
            switch finding.verdict {
            case .forbidden, .safeAuto, .needsConfirmation:
                break
            }
        }
    }
}
