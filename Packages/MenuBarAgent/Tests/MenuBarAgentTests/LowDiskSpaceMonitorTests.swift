import Foundation
import XCTest
@testable import MenuBarAgent

final class LowDiskSpaceMonitorTests: XCTestCase {
    func testNotifiesWhenBelowThreshold() async {
        let clock = TestClock(Date(timeIntervalSince1970: 0))
        let poster = RecordingNotificationPoster()
        let provider = MutableDiskSpaceProvider(free: 1_000_000_000, total: 100_000_000_000)
        let monitor = LowDiskSpaceMonitor(
            threshold: LowDiskSpaceThreshold(minimumFreeBytes: 10_000_000_000, minimumFreeFraction: nil),
            cooldown: 3_600,
            diskSpaceProvider: provider,
            notifier: poster,
            clock: clock
        )

        let isLow = await monitor.checkNow()
        XCTAssertTrue(isLow)
        let posts = await poster.posts
        XCTAssertEqual(posts.count, 1)
    }

    func testDoesNotNotifyWhenAboveThreshold() async {
        let clock = TestClock(Date(timeIntervalSince1970: 0))
        let poster = RecordingNotificationPoster()
        let provider = MutableDiskSpaceProvider(free: 50_000_000_000, total: 100_000_000_000)
        let monitor = LowDiskSpaceMonitor(
            threshold: LowDiskSpaceThreshold(minimumFreeBytes: 10_000_000_000, minimumFreeFraction: nil),
            diskSpaceProvider: provider,
            notifier: poster,
            clock: clock
        )

        let isLow = await monitor.checkNow()
        XCTAssertFalse(isLow)
        let posts = await poster.posts
        XCTAssertTrue(posts.isEmpty)
    }

    func testCooldownSuppressesRepeatNotificationsWhileStillLow() async {
        let clock = TestClock(Date(timeIntervalSince1970: 0))
        let poster = RecordingNotificationPoster()
        let provider = MutableDiskSpaceProvider(free: 1_000_000_000, total: 100_000_000_000)
        let monitor = LowDiskSpaceMonitor(
            threshold: LowDiskSpaceThreshold(minimumFreeBytes: 10_000_000_000, minimumFreeFraction: nil),
            cooldown: 3_600,
            diskSpaceProvider: provider,
            notifier: poster,
            clock: clock
        )

        _ = await monitor.checkNow()
        clock.advance(by: 60) // 1 minute later -- well within the 1-hour cooldown
        _ = await monitor.checkNow()

        let postsAfterTwoChecks = await poster.posts
        XCTAssertEqual(postsAfterTwoChecks.count, 1, "cooldown should suppress the second notification")

        clock.advance(by: 3_600) // cooldown fully elapsed
        _ = await monitor.checkNow()
        let postsAfterCooldownElapsed = await poster.posts
        XCTAssertEqual(postsAfterCooldownElapsed.count, 2)
    }

    func testRecoveringAboveThresholdResetsCooldownForTheNextLowPeriod() async {
        let clock = TestClock(Date(timeIntervalSince1970: 0))
        let poster = RecordingNotificationPoster()
        let provider = MutableDiskSpaceProvider(free: 1_000_000_000, total: 100_000_000_000)
        let monitor = LowDiskSpaceMonitor(
            threshold: LowDiskSpaceThreshold(minimumFreeBytes: 10_000_000_000, minimumFreeFraction: nil),
            cooldown: 3_600,
            diskSpaceProvider: provider,
            notifier: poster,
            clock: clock
        )

        _ = await monitor.checkNow() // low -> notifies (post #1)

        provider.setFree(50_000_000_000) // recovers above threshold
        _ = await monitor.checkNow() // not low -> resets internal cooldown state

        provider.setFree(1_000_000_000) // goes low again
        clock.advance(by: 1) // nowhere near the 1-hour cooldown, were it still active
        _ = await monitor.checkNow() // should notify again (post #2)

        let posts = await poster.posts
        XCTAssertEqual(posts.count, 2, "recovering resets cooldown, so the next low condition notifies immediately")
    }

    func testUnreadableDiskSpaceIsTreatedAsNotLowRatherThanCrashing() async {
        struct ThrowingProvider: DiskSpaceProviding {
            func freeAndTotalBytes(atPath path: String) throws -> (free: Int64, total: Int64) {
                throw DiskSpaceError.statfsFailed(errno: 2)
            }
        }
        let poster = RecordingNotificationPoster()
        let monitor = LowDiskSpaceMonitor(
            diskSpaceProvider: ThrowingProvider(),
            notifier: poster
        )

        let isLow = await monitor.checkNow()
        XCTAssertFalse(isLow)
        let posts = await poster.posts
        XCTAssertTrue(posts.isEmpty)
    }
}
