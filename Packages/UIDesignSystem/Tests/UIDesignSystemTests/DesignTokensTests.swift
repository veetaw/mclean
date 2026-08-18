import XCTest
@testable import UIDesignSystem

final class DesignTokensTests: XCTestCase {
    // MARK: Spacing

    func testSpacingScaleIsMonotonicallyIncreasing() {
        let scale: [CGFloat] = [
            DSSpacing.xxSmall,
            DSSpacing.xSmall,
            DSSpacing.small,
            DSSpacing.medium,
            DSSpacing.large,
            DSSpacing.xLarge,
            DSSpacing.xxLarge,
        ]
        for (lhs, rhs) in zip(scale, scale.dropFirst()) {
            XCTAssertLessThan(lhs, rhs, "Spacing scale must be strictly increasing")
        }
    }

    func testSpacingBaseUnit() {
        // Every token should be a positive multiple of 4pt, matching the
        // rest of the token scales.
        for value in [DSSpacing.xxSmall, DSSpacing.xSmall, DSSpacing.small, DSSpacing.medium, DSSpacing.large, DSSpacing.xLarge, DSSpacing.xxLarge] {
            XCTAssertGreaterThan(value, 0)
            XCTAssertEqual(value.truncatingRemainder(dividingBy: 4), 0)
        }
    }

    // MARK: Corner radius

    func testCornerRadiusScaleIsMonotonicallyIncreasing() {
        let scale: [CGFloat] = [DSCornerRadius.small, DSCornerRadius.medium, DSCornerRadius.large, DSCornerRadius.xLarge]
        for (lhs, rhs) in zip(scale, scale.dropFirst()) {
            XCTAssertLessThan(lhs, rhs)
        }
        XCTAssertGreaterThan(DSCornerRadius.pill, DSCornerRadius.xLarge)
    }
}
