import XCTest
@testable import SafetyRules

final class DenylistTests: XCTestCase {
    func testSystemPathIsForbidden() {
        XCTAssertNotNil(Denylist.forbiddenReason(forPath: "/System/Library/CoreServices"))
    }

    func testUsrIsForbiddenExceptUsrLocal() {
        XCTAssertNotNil(Denylist.forbiddenReason(forPath: "/usr/bin/ls"))
        XCTAssertNil(Denylist.forbiddenReason(forPath: "/usr/local/bin/brew"))
    }

    func testKeychainsAreForbidden() {
        XCTAssertNotNil(Denylist.forbiddenReason(forPath: "/Library/Keychains/login.keychain-db"))
    }

    func testOrdinaryUserCachePathIsNotForbidden() {
        XCTAssertNil(Denylist.forbiddenReason(forPath: "/Users/someone/Library/Caches/com.example.app"))
    }

    func testKextFilenamePatternIsForbiddenAnywhere() {
        XCTAssertNotNil(Denylist.forbiddenReason(forPath: "/Users/someone/random/Thing.kext"))
    }

    func testBootVolumeRootDetection() {
        XCTAssertTrue(Denylist.isLikelyBootVolumeRoot("/"))
        XCTAssertTrue(Denylist.isLikelyBootVolumeRoot("/Volumes/Macintosh HD"))
        XCTAssertFalse(Denylist.isLikelyBootVolumeRoot("/Volumes/Macintosh HD/Users/someone"))
    }
}

final class SafetyClassifierTests: XCTestCase {
    func testForbiddenPathClassifiesAsForbidden() {
        let classifier = SafetyClassifier()
        let item = ScanItemFixture.make(path: "/System/Library/CoreServices/Foo")
        guard case .forbidden = classifier.classify(item) else {
            return XCTFail("Expected .forbidden")
        }
    }

    func testOrdinaryPathDefaultsToNeedsConfirmation() {
        let classifier = SafetyClassifier()
        let item = ScanItemFixture.make(path: "/Users/someone/Library/Caches/com.example.app")
        guard case .needsConfirmation = classifier.classify(item) else {
            return XCTFail("Expected .needsConfirmation as the safe default")
        }
    }
}
