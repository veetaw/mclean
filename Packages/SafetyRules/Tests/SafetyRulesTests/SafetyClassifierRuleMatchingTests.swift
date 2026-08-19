import CoreScanEngine
import XCTest
@testable import SafetyRules

/// Covers the checkpoint 4 rule-matching behavior of `SafetyClassifier`:
/// glob/age matching, and the conservative merge across official/user
/// rules (needs-confirmation always wins over safe-auto for the same
/// item, regardless of source).
final class SafetyClassifierRuleMatchingTests: XCTestCase {
    private func item(path: String, daysOld: Int?) -> ScanItem {
        let lastUsed = daysOld.map {
            LastUsedEvidence(date: Calendar.current.date(byAdding: .day, value: -$0, to: Date())!, source: .filesystemMTime)
        }
        return ScanItemFixture.make(path: path, reason: "test").withLastUsed(lastUsed)
    }

    func testMatchingSafeAutoRuleYieldsSafeAutoVerdict() {
        let rule = SafetyRule(
            id: "test.safe-auto",
            description: "test",
            classification: .safeAuto,
            match: .init(pathGlob: "/tmp/scratch/**", minimumAgeDays: nil),
            introducedInVersion: 1
        )
        let classifier = SafetyClassifier(rules: [SourcedRule(rule: rule, source: .official)])
        let verdict = classifier.classify(item(path: "/tmp/scratch/foo", daysOld: nil))
        guard case .safeAuto(let ruleID) = verdict else { return XCTFail("expected .safeAuto, got \(verdict)") }
        XCTAssertEqual(ruleID, "test.safe-auto")
    }

    func testAgeRequirementFailsClosedWithNoLastUsedEvidence() {
        let rule = SafetyRule(
            id: "test.aged",
            description: "test",
            classification: .safeAuto,
            match: .init(pathGlob: "/tmp/scratch/**", minimumAgeDays: 30),
            introducedInVersion: 1
        )
        let classifier = SafetyClassifier(rules: [SourcedRule(rule: rule, source: .official)])
        let verdict = classifier.classify(item(path: "/tmp/scratch/foo", daysOld: nil))
        guard case .needsConfirmation = verdict else { return XCTFail("expected fail-closed .needsConfirmation, got \(verdict)") }
    }

    func testAgeRequirementRespectsThreshold() {
        let rule = SafetyRule(
            id: "test.aged",
            description: "test",
            classification: .safeAuto,
            match: .init(pathGlob: "/tmp/scratch/**", minimumAgeDays: 30),
            introducedInVersion: 1
        )
        let classifier = SafetyClassifier(rules: [SourcedRule(rule: rule, source: .official)])

        guard case .needsConfirmation = classifier.classify(item(path: "/tmp/scratch/foo", daysOld: 10)) else {
            return XCTFail("10-day-old item shouldn't satisfy a 30-day minimum")
        }
        guard case .safeAuto = classifier.classify(item(path: "/tmp/scratch/foo", daysOld: 45)) else {
            return XCTFail("45-day-old item should satisfy a 30-day minimum")
        }
    }

    func testConservativeMerge_userNeedsConfirmationBeatsOfficialSafeAuto() {
        let officialSafeAuto = SafetyRule(
            id: "official.broad-safe-auto",
            description: "official says safe",
            classification: .safeAuto,
            match: .init(pathGlob: "/tmp/scratch/**", minimumAgeDays: nil),
            introducedInVersion: 1
        )
        let userNeedsConfirmation = SafetyRule(
            id: "user.narrow-caution",
            description: "user wants to double check this specific subfolder",
            classification: .needsConfirmation,
            match: .init(pathGlob: "/tmp/scratch/important/**", minimumAgeDays: nil),
            introducedInVersion: 1
        )
        let classifier = SafetyClassifier(rules: [
            SourcedRule(rule: officialSafeAuto, source: .official),
            SourcedRule(rule: userNeedsConfirmation, source: .user),
        ])

        // Outside the user's narrower rule: official safe-auto applies.
        guard case .safeAuto = classifier.classify(item(path: "/tmp/scratch/other", daysOld: nil)) else {
            return XCTFail("expected safe-auto outside the user's restriction")
        }
        // Inside the user's narrower rule: needs-confirmation wins, even
        // though an official safe-auto rule also matches.
        guard case .needsConfirmation = classifier.classify(item(path: "/tmp/scratch/important/secret", daysOld: nil)) else {
            return XCTFail("user's needs-confirmation rule should override official safe-auto for an overlapping match")
        }
    }

    func testConservativeMerge_userCannotLoosenOfficialNeedsConfirmationIntoSafeAuto() {
        let officialNeedsConfirmation = SafetyRule(
            id: "official.caution",
            description: "official wants confirmation here",
            classification: .needsConfirmation,
            match: .init(pathGlob: "/tmp/scratch/**", minimumAgeDays: nil),
            introducedInVersion: 1
        )
        let userSafeAuto = SafetyRule(
            id: "user.trying-to-loosen",
            description: "user wants this auto-cleaned",
            classification: .safeAuto,
            match: .init(pathGlob: "/tmp/scratch/**", minimumAgeDays: nil),
            introducedInVersion: 1
        )
        let classifier = SafetyClassifier(rules: [
            SourcedRule(rule: officialNeedsConfirmation, source: .official),
            SourcedRule(rule: userSafeAuto, source: .user),
        ])

        guard case .needsConfirmation = classifier.classify(item(path: "/tmp/scratch/foo", daysOld: nil)) else {
            return XCTFail("a user safe-auto rule must never override an official needs-confirmation rule for the same item")
        }
    }

    func testDenylistAlwaysWinsRegardlessOfRules() {
        let userSafeAuto = SafetyRule(
            id: "user.trying-to-clean-system",
            description: "user rule attempting to cover a system path",
            classification: .safeAuto,
            match: .init(pathGlob: "/System/**", minimumAgeDays: nil),
            introducedInVersion: 1
        )
        let classifier = SafetyClassifier(rules: [SourcedRule(rule: userSafeAuto, source: .user)])
        guard case .forbidden = classifier.classify(item(path: "/System/Library/CoreServices/Foo", daysOld: nil)) else {
            return XCTFail("Denylist must win over any rule, no matter what the rule file says")
        }
    }

    func testNonBootVolumeDowngradesSafeAutoToNeedsConfirmation() {
        let rule = SafetyRule(
            id: "test.safe-auto",
            description: "test",
            classification: .safeAuto,
            match: .init(pathGlob: "/Volumes/**", minimumAgeDays: nil),
            introducedInVersion: 1
        )
        let classifier = SafetyClassifier(rules: [SourcedRule(rule: rule, source: .official)])
        let verdict = classifier.classify(item(path: "/Volumes/ExternalDrive/cache/foo", daysOld: nil))
        guard case .needsConfirmation = verdict else {
            return XCTFail("expected safe-auto to be downgraded on a non-boot volume, got \(verdict)")
        }
    }
}

extension ScanItem {
    /// Test-only convenience to produce a copy with different `lastUsed`
    /// evidence, since `ScanItem`'s stored properties are all `let`.
    func withLastUsed(_ lastUsed: LastUsedEvidence?) -> ScanItem {
        ScanItem(
            id: id,
            path: path,
            sizeBytes: sizeBytes,
            sourceDetectorID: sourceDetectorID,
            category: category,
            lastUsed: lastUsed,
            reason: reason
        )
    }
}
