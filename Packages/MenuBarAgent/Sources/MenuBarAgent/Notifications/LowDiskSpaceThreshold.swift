import Foundation

/// Configurable low-disk-space threshold. Triggers "low" if free space drops
/// below an absolute byte figure, below a fraction of total capacity, or
/// either -- when both are configured, crossing either one counts as low.
public struct LowDiskSpaceThreshold: Sendable, Hashable {
    public var minimumFreeBytes: Int64?
    public var minimumFreeFraction: Double?

    public init(minimumFreeBytes: Int64? = nil, minimumFreeFraction: Double? = nil) {
        self.minimumFreeBytes = minimumFreeBytes
        self.minimumFreeFraction = minimumFreeFraction
    }

    /// 10 GB free, or 10% of total capacity, whichever is hit first.
    public static let `default` = LowDiskSpaceThreshold(
        minimumFreeBytes: 10_000_000_000,
        minimumFreeFraction: 0.10
    )

    public func isLow(free: Int64, total: Int64) -> Bool {
        if let minimumFreeBytes, free < minimumFreeBytes {
            return true
        }
        if let minimumFreeFraction, total > 0, Double(free) / Double(total) < minimumFreeFraction {
            return true
        }
        return false
    }
}
