import CoreScanEngine
import Foundation
import XCTest
@testable import MenuBarAgent

private struct FakeDetector: Detector {
    let id: String
    let displayName = "Fake"
    let category = DetectorCategory.systemJunk
    let items: [ScanItem]

    func scan(context: ScanContext) async throws -> [ScanItem] {
        items
    }
}

final class HealthCheckDueCalculatorTests: XCTestCase {
    func testDueWhenNeverRun() {
        let calculator = HealthCheckDueCalculator()
        XCTAssertTrue(calculator.isDue(now: Date(), lastRunAt: nil, schedule: .weekly))
    }

    func testNotDueBeforeIntervalElapses() {
        let calculator = HealthCheckDueCalculator()
        let last = Date(timeIntervalSince1970: 0)
        let now = last.addingTimeInterval(HealthCheckSchedule.weekly.interval - 1)
        XCTAssertFalse(calculator.isDue(now: now, lastRunAt: last, schedule: .weekly))
    }

    func testDueOnceIntervalElapses() {
        let calculator = HealthCheckDueCalculator()
        let last = Date(timeIntervalSince1970: 0)
        let now = last.addingTimeInterval(HealthCheckSchedule.weekly.interval)
        XCTAssertTrue(calculator.isDue(now: now, lastRunAt: last, schedule: .weekly))
    }
}

final class HealthCheckSchedulerTests: XCTestCase {
    func testRunIfDueRunsOnFirstCallAndPostsASummary() async {
        let engine = ScanEngine()
        await engine.register(FakeDetector(
            id: "test.fake",
            items: [ScanItem(path: "/tmp/a", sizeBytes: 1_000, sourceDetectorID: "test.fake", category: "Test", lastUsed: nil, reason: "test")]
        ))
        let clock = TestClock(Date(timeIntervalSince1970: 0))
        let poster = RecordingNotificationPoster()
        let scheduler = HealthCheckScheduler(
            schedule: .weekly,
            scanEngine: engine,
            scanContext: ScanContext(roots: ["/tmp"]),
            notifier: poster,
            clock: clock
        )

        let ran = await scheduler.runIfDue()
        XCTAssertTrue(ran)
        let posts = await poster.posts
        XCTAssertEqual(posts.count, 1)
        XCTAssertTrue(posts[0].body.contains("1"), "summary body should mention the item count")
    }

    func testRunIfDueSkipsWhenNotYetDue() async {
        let engine = ScanEngine()
        let clock = TestClock(Date(timeIntervalSince1970: 0))
        let poster = RecordingNotificationPoster()
        let scheduler = HealthCheckScheduler(
            schedule: .weekly,
            scanEngine: engine,
            scanContext: ScanContext(roots: ["/tmp"]),
            notifier: poster,
            clock: clock
        )

        _ = await scheduler.runIfDue()
        clock.advance(by: 60) // far short of a week
        let ranAgain = await scheduler.runIfDue()

        XCTAssertFalse(ranAgain)
        let posts = await poster.posts
        XCTAssertEqual(posts.count, 1, "no second scan/notification until the schedule says it's due")
    }

    func testRunIfDueRunsAgainOnceIntervalElapses() async {
        let engine = ScanEngine()
        let clock = TestClock(Date(timeIntervalSince1970: 0))
        let poster = RecordingNotificationPoster()
        let scheduler = HealthCheckScheduler(
            schedule: .weekly,
            scanEngine: engine,
            scanContext: ScanContext(roots: ["/tmp"]),
            notifier: poster,
            clock: clock
        )

        _ = await scheduler.runIfDue()
        clock.advance(by: HealthCheckSchedule.weekly.interval)
        let ranAgain = await scheduler.runIfDue()

        XCTAssertTrue(ranAgain)
        let posts = await poster.posts
        XCTAssertEqual(posts.count, 2)
    }

    func testFailedDetectorsAreReportedWithoutAbortingTheSummary() async {
        struct ThrowingDetector: Detector {
            let id = "test.throws"
            let displayName = "Throws"
            let category = DetectorCategory.systemJunk
            func scan(context: ScanContext) async throws -> [ScanItem] {
                struct Boom: Error {}
                throw Boom()
            }
        }
        let engine = ScanEngine()
        await engine.register(ThrowingDetector())
        let clock = TestClock(Date(timeIntervalSince1970: 0))
        let poster = RecordingNotificationPoster()
        let scheduler = HealthCheckScheduler(
            schedule: .weekly,
            scanEngine: engine,
            scanContext: ScanContext(roots: ["/tmp"]),
            notifier: poster,
            clock: clock
        )

        let ran = await scheduler.runIfDue()
        XCTAssertTrue(ran)
        let posts = await poster.posts
        XCTAssertEqual(posts.count, 1, "a failing detector must not prevent the summary notification")
    }
}
