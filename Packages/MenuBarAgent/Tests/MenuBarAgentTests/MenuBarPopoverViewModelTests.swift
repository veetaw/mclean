import Foundation
import XCTest
@testable import MenuBarAgent

private struct FakeSystemStatsProviding: SystemStatsProviding {
    let snapshotToReturn: SystemStatsSnapshot
    func snapshot() async -> SystemStatsSnapshot { snapshotToReturn }
}

private struct FakeQuarantineSummaryProviding: QuarantineSummaryProviding {
    let summaryToReturn: QuarantineSummary
    func summary() async -> QuarantineSummary { summaryToReturn }
}

@MainActor
final class MenuBarPopoverViewModelTests: XCTestCase {
    func testRefreshPopulatesFormattedText() async {
        let snapshot = SystemStatsSnapshot(
            takenAt: Date(),
            diskSpace: .available(DiskSpaceSnapshot(freeBytes: 10_000_000_000, totalBytes: 100_000_000_000)),
            cpuUsageFraction: .available(0.42),
            memory: .available(MemorySnapshot(usedBytes: 8_000_000_000, totalBytes: 16_000_000_000)),
            battery: .available(BatterySnapshot(percentage: 80, isCharging: true))
        )
        let quarantine = QuarantineSummary(itemCount: 3, totalReclaimableBytes: 5_000_000, oldestPurgeEligibleAt: Date())

        let viewModel = MenuBarPopoverViewModel(
            statsProvider: FakeSystemStatsProviding(snapshotToReturn: snapshot),
            quarantineSummaryProvider: FakeQuarantineSummaryProviding(summaryToReturn: quarantine)
        )

        await viewModel.refresh()

        XCTAssertEqual(viewModel.cpuUsageText, "42%")
        XCTAssertTrue(viewModel.freeDiskSpaceText.contains("free"))
        XCTAssertTrue(viewModel.batteryText.contains("80%"))
        XCTAssertTrue(viewModel.batteryText.contains("charging"))
        XCTAssertTrue(viewModel.quarantineSummaryText.contains("3 items"))
    }

    func testUnavailableMetricsShowUnavailableRatherThanCrashingOrGuessing() async {
        let snapshot = SystemStatsSnapshot(
            takenAt: Date(),
            diskSpace: .unavailable(reason: "x"),
            cpuUsageFraction: .unavailable(reason: "x"),
            memory: .unavailable(reason: "x"),
            battery: .unavailable(reason: "x")
        )
        let viewModel = MenuBarPopoverViewModel(statsProvider: FakeSystemStatsProviding(snapshotToReturn: snapshot))

        await viewModel.refresh()

        XCTAssertEqual(viewModel.freeDiskSpaceText, "Unavailable")
        XCTAssertEqual(viewModel.cpuUsageText, "Unavailable")
        XCTAssertEqual(viewModel.memoryUsageText, "Unavailable")
        XCTAssertEqual(viewModel.batteryText, "Unavailable")
        XCTAssertEqual(viewModel.quarantineSummaryText, "Quarantine empty")
    }

    func testNoQuarantineProviderConfiguredShowsEmptyRatherThanCrashing() async {
        let snapshot = SystemStatsSnapshot(
            takenAt: Date(),
            diskSpace: .unavailable(reason: "x"),
            cpuUsageFraction: .unavailable(reason: "x"),
            memory: .unavailable(reason: "x"),
            battery: .unavailable(reason: "x")
        )
        let viewModel = MenuBarPopoverViewModel(statsProvider: FakeSystemStatsProviding(snapshotToReturn: snapshot))

        await viewModel.refresh()

        XCTAssertNil(viewModel.quarantineSummary)
        XCTAssertEqual(viewModel.quarantineSummaryText, "Quarantine empty")
    }
}
