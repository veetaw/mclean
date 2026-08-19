import XCTest
@testable import PrivacyCleaner

final class SitePreserveListTests: XCTestCase {
    func testExactMatchIsPreserved() {
        let list = SitePreserveList(domains: ["example.com"])
        XCTAssertTrue(list.preserves(host: "example.com"))
    }

    func testSubdomainOfPreservedDomainIsPreserved() {
        let list = SitePreserveList(domains: ["example.com"])
        XCTAssertTrue(list.preserves(host: "www.example.com"))
        XCTAssertTrue(list.preserves(host: "sub.example.com"))
    }

    func testUnrelatedDomainIsNotPreserved() {
        let list = SitePreserveList(domains: ["example.com"])
        XCTAssertFalse(list.preserves(host: "example.org"))
        XCTAssertFalse(list.preserves(host: "notexample.com"))
    }

    func testWildcardAndWWWPrefixesAreNormalizedOnInput() {
        let list = SitePreserveList(domains: ["*.example.com", "www.other.com"])
        XCTAssertTrue(list.preserves(host: "example.com"))
        XCTAssertTrue(list.preserves(host: "foo.example.com"))
        XCTAssertTrue(list.preserves(host: "other.com"))
    }

    func testCaseInsensitive() {
        let list = SitePreserveList(domains: ["Example.COM"])
        XCTAssertTrue(list.preserves(host: "EXAMPLE.com"))
    }

    func testEmptyListPreservesNothing() {
        let list = SitePreserveList()
        XCTAssertTrue(list.isEmpty)
        XCTAssertFalse(list.preserves(host: "example.com"))
    }
}
