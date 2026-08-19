import Foundation

/// A metric that may be legitimately unavailable -- missing entitlement, a
/// desktop Mac with no battery, a first-ever CPU sample with no delta yet, a
/// low-level syscall failing. Callers show "unavailable" for these rather
/// than crashing or displaying a misleading zero.
public enum MetricReading<Value: Sendable & Hashable>: Sendable, Hashable {
    case available(Value)
    case unavailable(reason: String)

    public var value: Value? {
        if case .available(let value) = self { return value }
        return nil
    }
}

public struct DiskSpaceSnapshot: Sendable, Hashable {
    public let freeBytes: Int64
    public let totalBytes: Int64

    public var freeFraction: Double {
        totalBytes > 0 ? Double(freeBytes) / Double(totalBytes) : 0
    }

    public init(freeBytes: Int64, totalBytes: Int64) {
        self.freeBytes = freeBytes
        self.totalBytes = totalBytes
    }
}

/// Best-effort approximation of "memory in active use": active + wired +
/// compressed pages. macOS's memory accounting doesn't have a single
/// universally agreed "used" figure (see Activity Monitor's own several
/// different numbers); this is the same approximation most lightweight
/// system monitors use.
public struct MemorySnapshot: Sendable, Hashable {
    public let usedBytes: Int64
    public let totalBytes: Int64

    public init(usedBytes: Int64, totalBytes: Int64) {
        self.usedBytes = usedBytes
        self.totalBytes = totalBytes
    }
}

public struct BatterySnapshot: Sendable, Hashable {
    public let percentage: Int
    public let isCharging: Bool

    public init(percentage: Int, isCharging: Bool) {
        self.percentage = percentage
        self.isCharging = isCharging
    }
}

/// A single point-in-time reading of the stats the popover shows. Every
/// field degrades to `.unavailable` independently -- one metric failing
/// never affects the others.
public struct SystemStatsSnapshot: Sendable, Hashable {
    public let takenAt: Date
    public let diskSpace: MetricReading<DiskSpaceSnapshot>
    public let cpuUsageFraction: MetricReading<Double>
    public let memory: MetricReading<MemorySnapshot>
    public let battery: MetricReading<BatterySnapshot>

    public init(
        takenAt: Date,
        diskSpace: MetricReading<DiskSpaceSnapshot>,
        cpuUsageFraction: MetricReading<Double>,
        memory: MetricReading<MemorySnapshot>,
        battery: MetricReading<BatterySnapshot>
    ) {
        self.takenAt = takenAt
        self.diskSpace = diskSpace
        self.cpuUsageFraction = cpuUsageFraction
        self.memory = memory
        self.battery = battery
    }
}
