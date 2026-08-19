import Foundation
import XCTest
@testable import MenuBarAgent

/// Pure, deterministic tests for the debounce *decision* logic used to turn
/// bursts of FSEvents callbacks into a single coalesced signal -- no real
/// timers or waiting involved, everything is driven by fed-in timestamps.
final class EventCoalescerTests: XCTestCase {
    func testDoesNotFireBeforeQuietPeriodElapses() {
        var coalescer = EventCoalescer(quietPeriod: 5)
        let start = Date(timeIntervalSince1970: 0)
        coalescer.recordEvent(at: start)

        XCTAssertFalse(coalescer.shouldFire(at: start.addingTimeInterval(4)))
        XCTAssertTrue(coalescer.hasPendingEvent)
    }

    func testFiresOnceQuietPeriodElapses() {
        var coalescer = EventCoalescer(quietPeriod: 5)
        let start = Date(timeIntervalSince1970: 0)
        coalescer.recordEvent(at: start)

        XCTAssertTrue(coalescer.shouldFire(at: start.addingTimeInterval(5)))
        XCTAssertFalse(coalescer.hasPendingEvent)
    }

    func testFiringConsumesPendingStateSoItDoesNotFireTwice() {
        var coalescer = EventCoalescer(quietPeriod: 1)
        let start = Date(timeIntervalSince1970: 0)
        coalescer.recordEvent(at: start)

        XCTAssertTrue(coalescer.shouldFire(at: start.addingTimeInterval(1)))
        XCTAssertFalse(coalescer.shouldFire(at: start.addingTimeInterval(10)), "nothing new happened -- must not fire again")
    }

    func testBurstOfEventsCollapsesToASingleFireAfterTheLastOne() {
        var coalescer = EventCoalescer(quietPeriod: 2)
        let start = Date(timeIntervalSince1970: 0)
        coalescer.recordEvent(at: start)
        coalescer.recordEvent(at: start.addingTimeInterval(0.5))
        coalescer.recordEvent(at: start.addingTimeInterval(1.0))

        // Only 1.4s quiet since the *last* event (t=1.0) -- not yet.
        XCTAssertFalse(coalescer.shouldFire(at: start.addingTimeInterval(2.4)))
        // Now 2.0s quiet since the last event.
        XCTAssertTrue(coalescer.shouldFire(at: start.addingTimeInterval(3.0)))
    }

    func testNoEventEverRecordedNeverFires() {
        var coalescer = EventCoalescer(quietPeriod: 1)
        XCTAssertFalse(coalescer.shouldFire(at: Date()))
        XCTAssertFalse(coalescer.hasPendingEvent)
    }

    func testNewEventAfterAFireStartsAFreshPendingPeriod() {
        var coalescer = EventCoalescer(quietPeriod: 1)
        let start = Date(timeIntervalSince1970: 0)
        coalescer.recordEvent(at: start)
        XCTAssertTrue(coalescer.shouldFire(at: start.addingTimeInterval(1)))

        coalescer.recordEvent(at: start.addingTimeInterval(10))
        XCTAssertFalse(coalescer.shouldFire(at: start.addingTimeInterval(10.5)))
        XCTAssertTrue(coalescer.shouldFire(at: start.addingTimeInterval(11)))
    }
}
