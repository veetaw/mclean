import Darwin
import Foundation
import IOKit.ps

/// Real `SystemStatsProviding`, backed by low-level system APIs: `statfs`
/// for disk, `host_statistics`/`host_statistics64` for CPU/memory, IOKit
/// power-source APIs for battery. Every metric is independently best-effort:
/// a failure reading one never affects the others, and every failure
/// degrades to `.unavailable` rather than throwing or crashing.
///
/// An actor (not a struct) because CPU usage percentage requires a delta
/// between two samples -- `host_statistics` reports cumulative ticks since
/// boot, not an instantaneous load -- so this holds the previous sample as
/// actor-isolated mutable state.
public actor SystemStatsProvider: SystemStatsProviding {
    private let diskPath: String
    private let diskSpaceProvider: DiskSpaceProviding
    private var previousCPUTicks: host_cpu_load_info?

    public init(
        diskPath: String = NSHomeDirectory(),
        diskSpaceProvider: DiskSpaceProviding = StatfsDiskSpaceProvider()
    ) {
        self.diskPath = diskPath
        self.diskSpaceProvider = diskSpaceProvider
    }

    public func snapshot() async -> SystemStatsSnapshot {
        SystemStatsSnapshot(
            takenAt: Date(),
            diskSpace: diskSpaceReading(),
            cpuUsageFraction: cpuUsageReading(),
            memory: memoryReading(),
            battery: batteryReading()
        )
    }

    // MARK: - Disk

    private func diskSpaceReading() -> MetricReading<DiskSpaceSnapshot> {
        do {
            let (free, total) = try diskSpaceProvider.freeAndTotalBytes(atPath: diskPath)
            return .available(DiskSpaceSnapshot(freeBytes: free, totalBytes: total))
        } catch {
            return .unavailable(reason: "Could not read volume free space.")
        }
    }

    // MARK: - CPU

    private func cpuUsageReading() -> MetricReading<Double> {
        guard let current = Self.currentCPUTicks() else {
            return .unavailable(reason: "host_statistics unavailable.")
        }
        defer { previousCPUTicks = current }

        guard let previous = previousCPUTicks else {
            return .unavailable(reason: "Warming up (needs a second sample).")
        }

        // CPU_STATE_USER = 0, CPU_STATE_SYSTEM = 1, CPU_STATE_IDLE = 2, CPU_STATE_NICE = 3.
        let userDelta = Self.tickDelta(current.cpu_ticks.0, previous.cpu_ticks.0)
        let systemDelta = Self.tickDelta(current.cpu_ticks.1, previous.cpu_ticks.1)
        let idleDelta = Self.tickDelta(current.cpu_ticks.2, previous.cpu_ticks.2)
        let niceDelta = Self.tickDelta(current.cpu_ticks.3, previous.cpu_ticks.3)

        let busy = Double(userDelta) + Double(systemDelta) + Double(niceDelta)
        let total = busy + Double(idleDelta)
        guard total > 0 else {
            return .unavailable(reason: "No CPU tick delta available yet.")
        }
        return .available(min(max(busy / total, 0), 1))
    }

    private static func currentCPUTicks() -> host_cpu_load_info? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) { infoPtr -> kern_return_t in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, intPtr, &count)
            }
        }
        return result == KERN_SUCCESS ? info : nil
    }

    /// Tick counters are monotonically increasing `natural_t` (`UInt32`)
    /// values; guard against the pathological case (host suspend/resume,
    /// counter wraparound) where `current < previous` by treating it as "no
    /// usable delta" rather than underflowing.
    private static func tickDelta(_ current: UInt32, _ previous: UInt32) -> UInt32 {
        current >= previous ? current - previous : 0
    }

    // MARK: - Memory

    private func memoryReading() -> MetricReading<MemorySnapshot> {
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) { infoPtr -> kern_return_t in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            return .unavailable(reason: "host_statistics64 unavailable.")
        }

        // `getpagesize()` (a function call) rather than the `vm_kernel_page_size`
        // global (a mutable C var Swift 6 flags as not concurrency-safe to read
        // directly) -- both report the same value on Apple platforms.
        let pageSize = UInt64(getpagesize())
        let usedPages = UInt64(info.active_count) + UInt64(info.wire_count) + UInt64(info.compressor_page_count)
        let usedBytes = Int64(usedPages * pageSize)
        let totalBytes = Int64(ProcessInfo.processInfo.physicalMemory)
        return .available(MemorySnapshot(usedBytes: usedBytes, totalBytes: totalBytes))
    }

    // MARK: - Battery

    private func batteryReading() -> MetricReading<BatterySnapshot> {
        guard let snapshot = Self.readBatterySnapshot() else {
            return .unavailable(reason: "No battery present.")
        }
        return .available(snapshot)
    }

    private static func readBatterySnapshot() -> BatterySnapshot? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return nil }
        guard let sourcesList = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
              let source = sourcesList.first,
              let description = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: AnyObject]
        else {
            return nil
        }

        guard let percentage = description[kIOPSCurrentCapacityKey] as? Int else { return nil }
        let stateName = description[kIOPSPowerSourceStateKey] as? String
        let isCharging = stateName == kIOPSACPowerValue
        return BatterySnapshot(percentage: percentage, isCharging: isCharging)
    }
}
