import XCTest
@testable import SafetyRules

final class RuleFileLoaderTests: XCTestCase {
    private var tempRoot: URL!
    private var fakeBundleDir: URL!
    private var userRulesDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("RuleFileLoaderTests-\(UUID().uuidString)", isDirectory: true)
        fakeBundleDir = tempRoot.appendingPathComponent("FakeBundle", isDirectory: true)
        userRulesDir = tempRoot.appendingPathComponent("UserRules", isDirectory: true)
        try FileManager.default.createDirectory(at: fakeBundleDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
        try super.tearDownWithError()
    }

    private func writeFakeOfficialRules(_ yaml: String) throws {
        try yaml.write(to: fakeBundleDir.appendingPathComponent("official_rules.yaml"), atomically: true, encoding: .utf8)
    }

    // MARK: - Real bundled resource (integration check)

    func testRealBundledOfficialRulesLoadWithMatchingHash() {
        let loaded = RuleFileLoader.load(userRulesDirectory: userRulesDir)
        XCTAssertTrue(loaded.officialRulesIntegrityOK, "expected the shipped official_rules.yaml to match OfficialRulesIntegrity.expectedSHA256Hex")
        XCTAssertNil(loaded.warning)
        XCTAssertTrue(loaded.rules.contains { $0.source == .official })
    }

    // MARK: - User rule file creation

    func testUserRulesFileIsCreatedOnFirstLoad() {
        let fileURL = userRulesDir.appendingPathComponent("user_rules.yaml")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))

        _ = RuleFileLoader.load(userRulesDirectory: userRulesDir)

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        let contents = try? String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(contents?.contains("version: 1") == true)
    }

    func testExistingUserRulesAreParsedAndTaggedWithUserSource() throws {
        try FileManager.default.createDirectory(at: userRulesDir, withIntermediateDirectories: true)
        let yaml = """
        version: 1
        rules:
          - id: user.test-rule
            description: "test"
            classification: safe-auto
            match:
              pathGlob: "/tmp/my-scratch/**"
            introducedInVersion: 1
        """
        try yaml.write(to: userRulesDir.appendingPathComponent("user_rules.yaml"), atomically: true, encoding: .utf8)

        let loaded = RuleFileLoader.load(userRulesDirectory: userRulesDir, bundle: fakeBundle(withValidRules: true))

        let userRule = loaded.rules.first { $0.rule.id == "user.test-rule" }
        XCTAssertNotNil(userRule)
        XCTAssertEqual(userRule?.source, .user)
    }

    func testMalformedUserRulesFileDoesNotCrashAndYieldsAWarning() throws {
        try FileManager.default.createDirectory(at: userRulesDir, withIntermediateDirectories: true)
        try "not: [valid, yaml: for: this: schema".write(
            to: userRulesDir.appendingPathComponent("user_rules.yaml"),
            atomically: true,
            encoding: .utf8
        )

        let loaded = RuleFileLoader.load(userRulesDirectory: userRulesDir, bundle: fakeBundle(withValidRules: true))
        XCTAssertFalse(loaded.rules.contains { $0.source == .user })
        XCTAssertNotNil(loaded.warning)
    }

    // MARK: - Official rules integrity

    func testMismatchedOfficialHashDowngradesSafeAutoAndSetsWarning() throws {
        try writeFakeOfficialRules("""
        version: 1
        rules:
          - id: official.test-rule
            description: "test"
            classification: safe-auto
            match:
              pathGlob: "/tmp/anything/**"
            introducedInVersion: 1
        """)

        let loaded = RuleFileLoader.load(userRulesDirectory: userRulesDir, bundle: Bundle(url: fakeBundleDir)!)

        XCTAssertFalse(loaded.officialRulesIntegrityOK)
        XCTAssertNotNil(loaded.warning)

        let officialRule = loaded.rules.first { $0.rule.id == "official.test-rule" }
        XCTAssertEqual(officialRule?.rule.classification, .needsConfirmation, "safe-auto should be downgraded on a hash mismatch")
    }

    func testMissingOfficialFileYieldsNoOfficialRulesAndAWarning() {
        // fakeBundleDir exists but has no official_rules.yaml in it.
        let loaded = RuleFileLoader.load(userRulesDirectory: userRulesDir, bundle: Bundle(url: fakeBundleDir)!)
        XCTAssertFalse(loaded.officialRulesIntegrityOK)
        XCTAssertNotNil(loaded.warning)
        XCTAssertFalse(loaded.rules.contains { $0.source == .official })
    }

    // MARK: - Helpers

    private func fakeBundle(withValidRules: Bool) -> Bundle {
        if withValidRules {
            try? """
            version: 1
            rules: []
            """.write(to: fakeBundleDir.appendingPathComponent("official_rules.yaml"), atomically: true, encoding: .utf8)
        }
        return Bundle(url: fakeBundleDir)!
    }
}
