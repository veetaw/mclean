import Foundation
import XCTest
@testable import MenuBarAgent

/// Exercises the actor-level bridging on top of `EventCoalescer`: a fake
/// clock plus a fully test-controlled `Sleeping` (`GatedSleeper`) mean no
/// real waiting ever happens -- every "has time passed" decision is driven
/// by `TestClock.advance(by:)`, and every suspension point is resumed
/// explicitly by the test.
final class ChangeSignalCoalescerTests: XCTestCase {
    func testFiresOnlyOnceEnoughSimulatedTimeHasPassed() async {
        let clock = TestClock(Date(timeIntervalSince1970: 0))
        let sleeper = GatedSleeper()
        let counter = FireCounter()

        let coalescer = ChangeSignalCoalescer(quietPeriod: 5, clock: clock, sleeper: sleeper) {
            await counter.increment()
        }

        await coalescer.recordEvent()
        await pollUntil { await sleeper.waitingCount == 1 }

        // Only 2 simulated seconds pass -- releasing now must not fire.
        clock.advance(by: 2)
        await sleeper.release()
        await yieldMany()
        let countAfterEarlyRelease = await counter.count
        XCTAssertEqual(countAfterEarlyRelease, 0, "quiet period hasn't elapsed yet per the clock")

        // A fresh event reschedules the check; this time simulate enough elapsed time.
        await coalescer.recordEvent()
        await pollUntil { await sleeper.waitingCount == 1 }
        clock.advance(by: 5)
        await sleeper.release()

        await pollUntil { await counter.count == 1 }
    }

    func testBurstOfRecordEventsCollapsesIntoASingleFire() async {
        let clock = TestClock(Date(timeIntervalSince1970: 0))
        let sleeper = GatedSleeper()
        let counter = FireCounter()

        let coalescer = ChangeSignalCoalescer(quietPeriod: 5, clock: clock, sleeper: sleeper) {
            await counter.increment()
        }

        // First event parks a pending check.
        await coalescer.recordEvent()
        await pollUntil { await sleeper.waitingCount == 1 }

        // A second event arrives before the first check resolves: it must
        // cancel/replace the first pending check. Releasing the (now
        // cancelled) first waiter must not lead to a fire.
        await coalescer.recordEvent()
        await sleeper.release()
        clock.advance(by: 10)

        // The second pending check should still be outstanding (or about to
        // be); release it too, once parked -- this is the one that should fire.
        await pollUntil { await sleeper.waitingCount >= 1 }
        await sleeper.release()

        await pollUntil { await counter.count >= 1 }
        // Give any stray second fire a chance to (incorrectly) land before asserting.
        await yieldMany()
        let finalCount = await counter.count
        XCTAssertEqual(finalCount, 1, "a burst of events must collapse into exactly one fire")
    }

    func testCancelStopsAPendingCheckFromFiring() async {
        let clock = TestClock(Date(timeIntervalSince1970: 0))
        let sleeper = GatedSleeper()
        let counter = FireCounter()

        let coalescer = ChangeSignalCoalescer(quietPeriod: 5, clock: clock, sleeper: sleeper) {
            await counter.increment()
        }

        await coalescer.recordEvent()
        await pollUntil { await sleeper.waitingCount == 1 }

        await coalescer.cancel()
        clock.advance(by: 10)
        await sleeper.release()

        await yieldMany()
        let finalCount = await counter.count
        XCTAssertEqual(finalCount, 0)
    }
}
