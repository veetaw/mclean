import XCTest
@testable import SafetyRules

final class GlobMatcherTests: XCTestCase {
    func testSingleStarMatchesWithinOneComponent() {
        XCTAssertTrue(GlobMatcher.matches(pattern: "/Users/me/Caches/*", path: "/Users/me/Caches/foo"))
        XCTAssertFalse(GlobMatcher.matches(pattern: "/Users/me/Caches/*", path: "/Users/me/Caches/foo/bar"))
    }

    func testDoubleStarMatchesAcrossComponents() {
        XCTAssertTrue(GlobMatcher.matches(pattern: "/Users/me/Caches/**", path: "/Users/me/Caches/foo/bar/baz"))
        XCTAssertTrue(GlobMatcher.matches(pattern: "/Users/me/Caches/**", path: "/Users/me/Caches/foo"))
    }

    func testQuestionMarkMatchesExactlyOneCharacter() {
        XCTAssertTrue(GlobMatcher.matches(pattern: "/tmp/file?.txt", path: "/tmp/file1.txt"))
        XCTAssertFalse(GlobMatcher.matches(pattern: "/tmp/file?.txt", path: "/tmp/file12.txt"))
    }

    func testNonMatchingPrefixFails() {
        XCTAssertFalse(GlobMatcher.matches(pattern: "/Users/me/Caches/**", path: "/Users/someone-else/Caches/foo"))
    }

    func testRegexMetacharactersInPatternAreEscaped() {
        XCTAssertTrue(GlobMatcher.matches(pattern: "/tmp/a.b+c/*", path: "/tmp/a.b+c/x"))
        XCTAssertFalse(GlobMatcher.matches(pattern: "/tmp/a.b+c/*", path: "/tmp/aXbYc/x"))
    }

    func testMiddleDoubleStarSpansDirectories() {
        XCTAssertTrue(GlobMatcher.matches(pattern: "**/Xcode/DerivedData/**", path: "/Users/me/Library/Developer/Xcode/DerivedData/App-abc/Build"))
        XCTAssertFalse(GlobMatcher.matches(pattern: "**/Xcode/DerivedData/**", path: "/Users/me/Library/Developer/Xcode/Archives/App.xcarchive"))
    }
}
