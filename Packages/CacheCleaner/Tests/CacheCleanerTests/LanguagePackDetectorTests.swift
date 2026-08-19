import XCTest
import CoreScanEngine
@testable import CacheCleaner

final class LanguagePackDetectorTests: XCTestCase {
    var appsRoot: String!
    let fm = FileManager.default

    override func setUp() {
        super.setUp()
        appsRoot = TempHome.make()
    }

    override func tearDown() {
        TempHome.cleanup(appsRoot)
        appsRoot = nil
        super.tearDown()
    }

    func testFlagsLprojForLocaleNotInPreferredLanguages() async throws {
        fm.makeFile(appsRoot + "/Foo.app/Contents/Resources/it.lproj/Localizable.strings", contents: "x")

        let detector = LanguagePackDetector(applicationsRootPath: appsRoot, preferredLanguages: ["en-US"])
        let items = try await detector.scan(context: scanContext(roots: []))

        let item = items.first { $0.path == appsRoot + "/Foo.app/Contents/Resources/it.lproj" }
        XCTAssertNotNil(item)
        XCTAssertEqual(item?.sourceDetectorID, "junk.languagepacks.unused-lproj")
    }

    func testDoesNotFlagLocaleMatchingPreferredLanguagePrimarySubtagDespiteRegionMismatch() async throws {
        fm.makeFile(appsRoot + "/Foo.app/Contents/Resources/it.lproj/Localizable.strings", contents: "x")

        // Preferred is "it-IT", lproj is plain "it" — should still match on
        // the shared primary language subtag.
        let detector = LanguagePackDetector(applicationsRootPath: appsRoot, preferredLanguages: ["it-IT"])
        let items = try await detector.scan(context: scanContext(roots: []))

        XCTAssertFalse(items.contains { $0.path.hasSuffix("it.lproj") })
    }

    func testNeverFlagsBaseLproj() async throws {
        fm.makeFile(appsRoot + "/Foo.app/Contents/Resources/Base.lproj/MainMenu.nib", contents: "x")

        let detector = LanguagePackDetector(applicationsRootPath: appsRoot, preferredLanguages: ["it-IT"])
        let items = try await detector.scan(context: scanContext(roots: []))

        XCTAssertFalse(items.contains { $0.path.hasSuffix("Base.lproj") })
    }

    func testNeverFlagsEnglishLprojEvenWhenNotPreferred() async throws {
        fm.makeFile(appsRoot + "/Foo.app/Contents/Resources/en.lproj/Localizable.strings", contents: "x")
        fm.makeFile(appsRoot + "/Foo.app/Contents/Resources/en_GB.lproj/Localizable.strings", contents: "x")

        let detector = LanguagePackDetector(applicationsRootPath: appsRoot, preferredLanguages: ["it-IT"])
        let items = try await detector.scan(context: scanContext(roots: []))

        XCTAssertFalse(items.contains { $0.path.hasSuffix("en.lproj") })
        XCTAssertFalse(items.contains { $0.path.hasSuffix("en_GB.lproj") })
    }

    func testDoesNotDescendIntoNestedFrameworkResources() async throws {
        fm.makeFile(
            appsRoot + "/Foo.app/Contents/Frameworks/Bar.framework/Resources/it.lproj/Localizable.strings",
            contents: "x"
        )

        let detector = LanguagePackDetector(applicationsRootPath: appsRoot, preferredLanguages: ["en-US"])
        let items = try await detector.scan(context: scanContext(roots: []))

        XCTAssertTrue(items.isEmpty, "should only look at Contents/Resources directly, never nested frameworks/plugins")
    }

    func testIgnoresNonAppEntriesInApplicationsRoot() async throws {
        fm.makeFile(appsRoot + "/NotAnApp/Contents/Resources/it.lproj/Localizable.strings", contents: "x")

        let detector = LanguagePackDetector(applicationsRootPath: appsRoot, preferredLanguages: ["en-US"])
        let items = try await detector.scan(context: scanContext(roots: []))

        XCTAssertTrue(items.isEmpty)
    }

    func testRespectsCancellation() async throws {
        fm.makeFile(appsRoot + "/Foo.app/Contents/Resources/it.lproj/Localizable.strings", contents: "x")
        let root = appsRoot!

        let task = Task { () -> [ScanItem] in
            try await LanguagePackDetector(applicationsRootPath: root, preferredLanguages: ["en-US"])
                .scan(context: ScanContext(roots: []))
        }
        task.cancel()
        _ = try await task.value
    }
}
