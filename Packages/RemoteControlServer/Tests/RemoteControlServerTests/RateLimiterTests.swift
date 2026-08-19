import XCTest
@testable import RemoteControlServer

final class RateLimiterTests: XCTestCase {
    func testAllowsUpToLimitThenRejects() {
        let limiter = RateLimiter(maxRequests: 3, window: 60)
        let now = Date()
        XCTAssertTrue(limiter.allow("peer-a", now: now))
        XCTAssertTrue(limiter.allow("peer-a", now: now))
        XCTAssertTrue(limiter.allow("peer-a", now: now))
        XCTAssertFalse(limiter.allow("peer-a", now: now))
    }

    func testDifferentKeysAreIndependent() {
        let limiter = RateLimiter(maxRequests: 1, window: 60)
        let now = Date()
        XCTAssertTrue(limiter.allow("peer-a", now: now))
        XCTAssertTrue(limiter.allow("peer-b", now: now))
        XCTAssertFalse(limiter.allow("peer-a", now: now))
        XCTAssertFalse(limiter.allow("peer-b", now: now))
    }

    func testWindowExpiryAllowsAgain() {
        let limiter = RateLimiter(maxRequests: 1, window: 10)
        let start = Date()
        XCTAssertTrue(limiter.allow("peer-a", now: start))
        XCTAssertFalse(limiter.allow("peer-a", now: start.addingTimeInterval(5)))
        XCTAssertTrue(limiter.allow("peer-a", now: start.addingTimeInterval(11)))
    }
}
