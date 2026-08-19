import SafetyRules
import UIDesignSystem
import XCTest
@testable import MainAppUI

final class SafetyVerdictMappingTests: XCTestCase {
    func testForbiddenMapsToForbiddenTierAndIsNeverEligible() {
        let verdict = SafetyVerdict.forbidden(ruleID: "denylist.path", reason: "protected")
        XCTAssertEqual(verdict.uiTier, .forbidden)
        XCTAssertFalse(verdict.isEligibleForQuarantine)
    }

    func testSafeAutoMapsToSafeAutoTierAndIsEligible() {
        let verdict = SafetyVerdict.safeAuto(ruleID: "dev.system.expired-temp-files")
        XCTAssertEqual(verdict.uiTier, .safeAuto)
        XCTAssertTrue(verdict.isEligibleForQuarantine)
    }

    func testNeedsConfirmationMapsToNeedsConfirmationTierAndIsEligible() {
        let verdict = SafetyVerdict.needsConfirmation(reason: "no rule matched")
        XCTAssertEqual(verdict.uiTier, .needsConfirmation)
        XCTAssertTrue(verdict.isEligibleForQuarantine)
        XCTAssertTrue(verdict.uiDetail.contains("no rule matched"))
    }
}
