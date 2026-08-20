import CoreScanEngine
import Foundation
import SafetyRules

/// Read-only summary of what's currently sitting in quarantine, for display
/// in the menu bar popover (e.g. "12 items, 1.4 GB reclaimable, oldest
/// purges in 3 days").
///
/// This is the *only* way `MenuBarAgent` touches `SafetyRules`: strictly
/// read-only status display via `QuarantineManaging.listActive()`. This
/// package never calls `quarantine(_:retention:)`, `restore(_:)`, or
/// `purgeExpired()` -- it has no business triggering any of those actions on
/// its own, matching the "observes and notifies, nothing more" scope for
/// this whole module.
public struct QuarantineSummary: Sendable, Hashable {
    public let itemCount: Int
    public let totalReclaimableBytes: Int64
    public let oldestPurgeEligibleAt: Date?

    public init(itemCount: Int, totalReclaimableBytes: Int64, oldestPurgeEligibleAt: Date?) {
        self.itemCount = itemCount
        self.totalReclaimableBytes = totalReclaimableBytes
        self.oldestPurgeEligibleAt = oldestPurgeEligibleAt
    }
}

public protocol QuarantineSummaryProviding: Sendable {
    func summary() async -> QuarantineSummary
}

/// Real implementation, backed by any `QuarantineManaging` (typically
/// `SafetyRules.FileSystemQuarantineManager`). Read errors degrade to an
/// empty summary rather than throwing -- a popover stat is never allowed to
/// crash the menu bar.
public struct QuarantineSummaryReader: QuarantineSummaryProviding {
    private let manager: QuarantineManaging

    public init(manager: QuarantineManaging) {
        self.manager = manager
    }

    public func summary() async -> QuarantineSummary {
        guard let receipts = try? await manager.listActive() else {
            return QuarantineSummary(itemCount: 0, totalReclaimableBytes: 0, oldestPurgeEligibleAt: nil)
        }
        let total = receipts.reduce(Int64(0)) { $0 + ($1.sourceItem.sizeBytes ?? 0) }
        let oldest = receipts.map(\.purgeEligibleAt).min()
        return QuarantineSummary(itemCount: receipts.count, totalReclaimableBytes: total, oldestPurgeEligibleAt: oldest)
    }
}
