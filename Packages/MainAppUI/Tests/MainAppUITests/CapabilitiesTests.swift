import XCTest
@testable import MainAppUI

final class CapabilitiesTests: XCTestCase {
    func testAppStoreFlavorDisablesSandboxIncompatibleCapabilities() {
        let capabilities = Capabilities(flavor: .appStore)

        XCTAssertEqual(capabilities.flavor, .appStore)
        XCTAssertFalse(capabilities.canInstallPrivilegedHelper)
        XCTAssertFalse(capabilities.canRunRemoteControlServer)
        XCTAssertFalse(capabilities.canAccessOtherUsersFiles)
        XCTAssertFalse(capabilities.canReadTCCDatabase)
        XCTAssertFalse(capabilities.canRunShredder)
    }

    func testAppStoreFlavorStillAllowsSandboxSafeFeatures() {
        let capabilities = Capabilities(flavor: .appStore)

        XCTAssertTrue(capabilities.canRunMenuBarAgent)
        XCTAssertTrue(capabilities.canUseVirusTotalHashCheck)
    }

    func testDeveloperIDFlavorEnablesTheFullFeatureSet() {
        let capabilities = Capabilities(flavor: .developerID)

        XCTAssertEqual(capabilities.flavor, .developerID)
        XCTAssertTrue(capabilities.canInstallPrivilegedHelper)
        XCTAssertTrue(capabilities.canRunRemoteControlServer)
        XCTAssertTrue(capabilities.canAccessOtherUsersFiles)
        XCTAssertTrue(capabilities.canReadTCCDatabase)
        XCTAssertTrue(capabilities.canRunMenuBarAgent)
        XCTAssertTrue(capabilities.canUseVirusTotalHashCheck)
        XCTAssertTrue(capabilities.canRunShredder)
    }

    func testShredderIsDeveloperIDOnly() {
        // Shredder (Phase 5) does raw POSIX file I/O on a resolved path
        // rather than through a persisted security-scoped bookmark, which
        // hasn't been verified to behave correctly under the App Sandbox --
        // see the type doc comment on `Capabilities`.
        XCTAssertFalse(Capabilities(flavor: .appStore).canRunShredder)
        XCTAssertTrue(Capabilities(flavor: .developerID).canRunShredder)
    }

    func testCurrentResolvesToDeveloperIDInAPlainSwiftTestInvocation() {
        // A plain `swift test` invocation of this package never sets the
        // APPSTORE compilation condition (only the Xcode
        // `MCleanPro-AppStore` target does, via
        // `SWIFT_ACTIVE_COMPILATION_CONDITIONS` in App/project.yml), so
        // `.current` must resolve to `.developerID` here -- see
        // Package.swift's header comment.
        XCTAssertEqual(BuildFlavor.current, .developerID)
        XCTAssertEqual(Capabilities.current.flavor, .developerID)
    }

    func testReceiptSignalStubNeverThrowsAndReturnsABool() {
        // Not asserting a specific value -- this is a best-effort,
        // non-authoritative diagnostic (see its doc comment), and a
        // `swift test` binary has no App Store receipt either way. Only
        // asserting the call is safe and doesn't crash.
        _ = AppStoreReceiptSignal.receipptIndicatesAppStoreBuild()
    }
}
