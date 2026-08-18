import Foundation
import CoreScanEngine

/// Flags Simulator device data directories under
/// `~/Library/Developer/CoreSimulator/Devices/<UDID>` that haven't been
/// touched (booted/used) in a long time.
///
/// Purely filesystem-based — no dependency on `xcrun`/`simctl` being
/// available, since a device's data directory is enumerable directly.
/// `device.plist`, when present and readable, is used only to recover a
/// human-readable device name for `reason`; its absence never blocks
/// detection. There is no reliable on-disk "last booted" log, so this uses
/// the `data` subdirectory's mtime (falling back to `device.plist`, then
/// the device directory itself) as an honest, best-effort proxy.
public struct SimulatorDeviceDataDetector: Detector {
    public let id = "mobile.ios.simulator-devices-stale"
    public let displayName = "Simulator — stale device data"
    public let category: DetectorCategory = .mobileDev

    private let devicesRootPath: String
    private let staleThresholdDays: Int

    /// - Parameters:
    ///   - devicesRootPath: Defaults to
    ///     `~/Library/Developer/CoreSimulator/Devices`; overridable for tests.
    ///   - staleThresholdDays: Minimum inferred inactivity, in days, before
    ///     a device's data is flagged.
    public init(
        devicesRootPath: String = FSUtil.homeDirectory() + "/Library/Developer/CoreSimulator/Devices",
        staleThresholdDays: Int = 90
    ) {
        self.devicesRootPath = devicesRootPath
        self.staleThresholdDays = staleThresholdDays
    }

    public func scan(context: ScanContext) async throws -> [ScanItem] {
        guard FSUtil.exists(atPath: devicesRootPath, isDirectory: true) else { return [] }

        let root = URL(fileURLWithPath: devicesRootPath)
        let deviceDirs = FSUtil.subdirectories(of: root)
        guard !deviceDirs.isEmpty else { return [] }

        try Task.checkCancellation()
        let sizes = await FSUtil.sizes(of: deviceDirs, maxConcurrency: context.maxConcurrency)

        let now = Date()
        let cutoff = Calendar.current.date(byAdding: .day, value: -staleThresholdDays, to: now) ?? .distantPast

        var items: [ScanItem] = []
        for deviceDir in deviceDirs {
            try Task.checkCancellation()

            let plistPath = deviceDir.appendingPathComponent("device.plist").path
            let deviceName = Self.readDeviceName(plistPath: plistPath) ?? deviceDir.lastPathComponent

            let dataPath = deviceDir.appendingPathComponent("data").path
            let lastUsedDate = FSUtil.modificationDate(ofItemAt: dataPath)
                ?? FSUtil.modificationDate(ofItemAt: plistPath)
                ?? FSUtil.modificationDate(ofItemAt: deviceDir.path)

            guard let lastUsedDate, lastUsedDate < cutoff else { continue }
            let daysAgo = max(0, Int(now.timeIntervalSince(lastUsedDate) / 86_400))

            items.append(ScanItem(
                path: deviceDir.path,
                sizeBytes: sizes[deviceDir],
                sourceDetectorID: id,
                category: "Simulator — unbooted device data",
                lastUsed: LastUsedEvidence(date: lastUsedDate, source: .filesystemMTime),
                reason: """
                Simulator device "\(deviceName)" (\(deviceDir.lastPathComponent)) shows no \
                filesystem activity in ~\(daysAgo) days, suggesting it hasn't been booted \
                recently. There is no real boot log on disk, so this is inferred from mtime.
                """
            ))
        }
        return items
    }

    private static func readDeviceName(plistPath: String) -> String? {
        guard let data = FileManager.default.contents(atPath: plistPath),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        else { return nil }
        return plist["name"] as? String
    }
}
