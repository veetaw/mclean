import XCTest
@testable import UIDesignSystem

final class SafetyBadgeTests: XCTestCase {
    func testAllThreeSafetyRulesTiersAreRepresented() {
        // Mirrors SafetyRules.SafetyVerdict's three cases: forbidden,
        // safeAuto, needsConfirmation. If this fails, DSSafetyTier has
        // drifted out of sync with SafetyVerdict — update both.
        XCTAssertEqual(DSSafetyTier.allCases.count, 3)
        XCTAssertTrue(DSSafetyTier.allCases.contains(.forbidden))
        XCTAssertTrue(DSSafetyTier.allCases.contains(.safeAuto))
        XCTAssertTrue(DSSafetyTier.allCases.contains(.needsConfirmation))
    }

    func testEveryTierHasAUniqueNonEmptyLabel() {
        let labels = DSSafetyTier.allCases.map(\.label)
        XCTAssertTrue(labels.allSatisfy { !$0.isEmpty })
        XCTAssertEqual(Set(labels).count, labels.count, "Badge labels must be unique so tiers are never visually ambiguous")
    }

    func testEveryTierHasAUniqueSystemImage() {
        let symbols = DSSafetyTier.allCases.map(\.systemImage)
        XCTAssertEqual(Set(symbols).count, symbols.count, "Badge icons must be unique so tiers are never visually ambiguous")
    }

    func testForbiddenIsTheMostSevereLabel() {
        // `forbidden` is the one tier that must never look like a routine
        // secondary action — assert its copy explicitly signals refusal.
        XCTAssertTrue(DSSafetyTier.forbidden.label.lowercased().contains("never"))
    }
}
