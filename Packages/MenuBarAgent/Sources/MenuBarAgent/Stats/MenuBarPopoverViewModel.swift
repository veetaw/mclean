import Foundation
import Observation

/// SwiftUI-friendly view model backing the menu bar popover. Owns no UI
/// itself -- `MainAppUI` supplies the actual SwiftUI view and reads this
/// model's properties. `@MainActor`-isolated since it exists to back UI
/// state directly, and `@Observable` so SwiftUI views picking up its
/// properties invalidate automatically.
@MainActor
@Observable
public final class MenuBarPopoverViewModel {
    public private(set) var stats: SystemStatsSnapshot?
    public private(set) var quarantineSummary: QuarantineSummary?

    private let statsProvider: SystemStatsProviding
    private let quarantineSummaryProvider: QuarantineSummaryProviding?

    public init(
        statsProvider: SystemStatsProviding,
        quarantineSummaryProvider: QuarantineSummaryProviding? = nil
    ) {
        self.statsProvider = statsProvider
        self.quarantineSummaryProvider = quarantineSummaryProvider
    }

    /// Re-fetches everything. Cheap enough to call whenever the popover is
    /// about to be shown, or on a caller-owned low-frequency timer.
    public func refresh() async {
        stats = await statsProvider.snapshot()
        if let quarantineSummaryProvider {
            quarantineSummary = await quarantineSummaryProvider.summary()
        }
    }

    // MARK: - Display formatting

    public var freeDiskSpaceText: String {
        guard let value = stats?.diskSpace.value else { return "Unavailable" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return "\(formatter.string(fromByteCount: value.freeBytes)) free"
    }

    public var cpuUsageText: String {
        guard let value = stats?.cpuUsageFraction.value else { return "Unavailable" }
        return String(format: "%.0f%%", value * 100)
    }

    public var memoryUsageText: String {
        guard let value = stats?.memory.value else { return "Unavailable" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        return "\(formatter.string(fromByteCount: value.usedBytes)) used"
    }

    public var batteryText: String {
        guard let value = stats?.battery.value else { return "Unavailable" }
        return "\(value.percentage)%\(value.isCharging ? " (charging)" : "")"
    }

    public var quarantineSummaryText: String {
        guard let summary = quarantineSummary, summary.itemCount > 0 else { return "Quarantine empty" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let sizeText = formatter.string(fromByteCount: summary.totalReclaimableBytes)
        return "\(summary.itemCount) items in quarantine (\(sizeText))"
    }
}
