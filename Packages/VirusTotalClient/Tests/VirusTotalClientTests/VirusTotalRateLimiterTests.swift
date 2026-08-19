import Foundation
import XCTest
@testable import VirusTotalClient

/// Exercises `VirusTotalRateLimiter`'s real wait/backoff behavior using an
/// injectable `Clock`/`Sleeping` pair -- no test here ever blocks on real
/// wall-clock time, including the "day budget exhausted" case, which would
/// otherwise mean waiting up to 24 real hours.
final class VirusTotalRateLimiterTests: XCTestCase {
    func testAwaitSlot_withinBudget_neverSleeps() async throws {
        let clock = TestClock()
        let sleeper = FakeSleeper(clock: clock)
        let limiter = VirusTotalRateLimiter(
            limits: .init(requestsPerMinute: 4, requestsPerDay: 500),
            clock: clock,
            sleeper: sleeper
        )

        for _ in 0..<4 {
            try await limiter.awaitSlot()
        }

        let calls = await sleeper.sleepCalls
        XCTAssertTrue(calls.isEmpty, "should never sleep while under budget")
        let remaining = await limiter.remainingToday()
        XCTAssertEqual(remaining, 496)
    }

    func testAwaitSlot_perMinuteBudgetExhausted_waitsThenReservesSlot() async throws {
        let clock = TestClock()
        let sleeper = FakeSleeper(clock: clock)
        let limiter = VirusTotalRateLimiter(
            limits: .init(requestsPerMinute: 2, requestsPerDay: 500),
            clock: clock,
            sleeper: sleeper
        )

        try await limiter.awaitSlot()
        try await limiter.awaitSlot()
        // Budget for this minute is now exhausted -- the 3rd call must wait,
        // not fire immediately and not throw.
        try await limiter.awaitSlot()

        let calls = await sleeper.sleepCalls
        XCTAssertEqual(calls.count, 1, "exactly one bounded wait, not a spin loop")
        XCTAssertLessThanOrEqual(calls[0], 60, "wait is bounded by the minute window, not an arbitrary/huge duration")
        XCTAssertGreaterThan(calls[0], 0)
    }

    func testAwaitSlot_dayBudgetExhausted_waitsForDayWindowNotForever() async throws {
        let clock = TestClock()
        let sleeper = FakeSleeper(clock: clock)
        let limiter = VirusTotalRateLimiter(
            limits: .init(requestsPerMinute: 1000, requestsPerDay: 1),
            clock: clock,
            sleeper: sleeper
        )

        try await limiter.awaitSlot()
        try await limiter.awaitSlot()

        let calls = await sleeper.sleepCalls
        XCTAssertEqual(calls.count, 1)
        XCTAssertLessThanOrEqual(calls[0], 86400)
        XCTAssertGreaterThan(calls[0], 0)
    }

    func testAwaitSlot_afterWaiting_windowsActuallyReset() async throws {
        let clock = TestClock()
        let sleeper = FakeSleeper(clock: clock)
        let limiter = VirusTotalRateLimiter(
            limits: .init(requestsPerMinute: 1, requestsPerDay: 500),
            clock: clock,
            sleeper: sleeper
        )

        try await limiter.awaitSlot() // uses up the single per-minute slot
        try await limiter.awaitSlot() // must wait for the minute to roll over; this reserves the new window's single slot too

        // Advance further, simulating real time passing before the next
        // call -- once its own minute window has genuinely elapsed, it
        // should succeed without needing to wait again.
        clock.advance(by: 60)
        try await limiter.awaitSlot()

        let calls = await sleeper.sleepCalls
        XCTAssertEqual(calls.count, 1, "the third call should not need to wait again")
    }

    /// Uses the real system clock/sleeper (not the fakes) specifically to
    /// prove genuine `Task` cancellation is honored while parked waiting on
    /// the limiter -- but bounds the test's real running time by cancelling
    /// almost immediately, so this stays a fast test despite using real
    /// time.
    func testAwaitSlot_cancellationWhileWaiting_throwsPromptlyInsteadOfWaitingOutTheWindow() async throws {
        let limiter = VirusTotalRateLimiter(limits: .init(requestsPerMinute: 1, requestsPerDay: 500))
        try await limiter.awaitSlot() // fills the one slot for this minute

        let task = Task {
            try await limiter.awaitSlot()
        }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()

        let start = Date()
        do {
            try await task.value
            XCTFail("expected CancellationError")
        } catch is CancellationError {
            // expected
        } catch {
            XCTFail("expected CancellationError, got \(error)")
        }
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 5.0, "cancellation must be observed promptly, not after waiting out the ~60s window")
    }

    func testRemainingToday_decreasesAsSlotsAreReserved() async throws {
        let limiter = VirusTotalRateLimiter(limits: .init(requestsPerMinute: 500, requestsPerDay: 500))
        let before = await limiter.remainingToday()
        XCTAssertEqual(before, 500)
        try await limiter.awaitSlot()
        let after = await limiter.remainingToday()
        XCTAssertEqual(after, 499)
    }
}
