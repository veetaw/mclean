import Foundation
import CoreScanEngine

/// Flags iOS/watchOS/tvOS Simulator runtime images (installed via Xcode ->
/// Platforms) that look unused: either no simulator device references them
/// at all, or every device that does hasn't shown filesystem activity in a
/// long time.
///
/// Uses `xcrun simctl list runtimes -j` / `xcrun simctl list devices -j` when
/// `xcrun` is available and returns JSON; if `xcrun` is missing, not
/// executable, or the command fails (no Xcode installed, license not
/// accepted, etc.) this detector returns no items rather than throwing —
/// Simulator tooling is entirely optional on a given machine.
public struct SimulatorRuntimeDetector: Detector {
    public let id = "mobile.ios.simulator-runtimes-unused"
    public let displayName = "Simulator — unused iOS/watchOS/tvOS runtimes"
    public let category: DetectorCategory = .mobileDev

    private let xcrunPath: String
    private let commandRunner: CommandRunning
    private let staleThresholdDays: Int

    /// - Parameters:
    ///   - xcrunPath: Defaults to `/usr/bin/xcrun`.
    ///   - commandRunner: Injectable for tests, so this detector can be
    ///     exercised without Xcode installed.
    ///   - staleThresholdDays: Minimum inactivity, in days, across every
    ///     device using a runtime before that runtime is flagged (runtimes
    ///     with zero associated devices are always flagged, regardless).
    public init(
        xcrunPath: String = "/usr/bin/xcrun",
        commandRunner: CommandRunning = ProcessCommandRunner(),
        staleThresholdDays: Int = 120
    ) {
        self.xcrunPath = xcrunPath
        self.commandRunner = commandRunner
        self.staleThresholdDays = staleThresholdDays
    }

    public func scan(context: ScanContext) async throws -> [ScanItem] {
        guard FileManager.default.isExecutableFile(atPath: xcrunPath) else { return [] }

        let runtimesOutput: String
        let devicesOutput: String
        do {
            runtimesOutput = try commandRunner.run(
                executablePath: xcrunPath,
                arguments: ["simctl", "list", "runtimes", "-j"]
            )
            devicesOutput = try commandRunner.run(
                executablePath: xcrunPath,
                arguments: ["simctl", "list", "devices", "-j"]
            )
        } catch {
            // simctl unusable on this machine — degrade to "no findings"
            // rather than surfacing a process-launch error to the UI.
            return []
        }

        guard let runtimesData = runtimesOutput.data(using: .utf8),
              let runtimesResponse = try? JSONDecoder().decode(SimctlRuntimesResponse.self, from: runtimesData)
        else { return [] }
        let runtimes = runtimesResponse.runtimes
        guard !runtimes.isEmpty else { return [] }

        var devicesByRuntime: [String: [SimctlDevice]] = [:]
        if let devicesData = devicesOutput.data(using: .utf8),
           let devicesResponse = try? JSONDecoder().decode(SimctlDevicesResponse.self, from: devicesData) {
            devicesByRuntime = devicesResponse.devices
        }

        let now = Date()
        let cutoff = Calendar.current.date(byAdding: .day, value: -staleThresholdDays, to: now) ?? .distantPast

        var items: [ScanItem] = []
        for runtime in runtimes {
            try Task.checkCancellation()

            let devices = devicesByRuntime[runtime.identifier] ?? []
            let lastUsedDate: Date?
            let activitySummary: String

            if devices.isEmpty {
                lastUsedDate = nil
                activitySummary = "No simulator devices reference this runtime."
            } else {
                let dataPaths = devices.compactMap(\.dataPath)
                let latest = FSUtil.latestModificationDate(among: dataPaths)
                guard let latest, latest < cutoff else { continue }
                lastUsedDate = latest
                let daysAgo = max(0, Int(now.timeIntervalSince(latest) / 86_400))
                activitySummary = "\(devices.count) simulator device(s) reference this runtime, " +
                    "but none show data activity in ~\(daysAgo) days."
            }

            let runtimePath = runtime.runtimeRoot ?? runtime.bundlePath
            var sizeBytes: Int64?
            if let runtimePath {
                sizeBytes = await FSUtil.directorySize(at: URL(fileURLWithPath: runtimePath))
            }

            items.append(ScanItem(
                path: runtimePath ?? "simctl-runtime:\(runtime.identifier)",
                sizeBytes: sizeBytes,
                sourceDetectorID: id,
                category: "Simulator — unused runtime",
                lastUsed: lastUsedDate.map { LastUsedEvidence(date: $0, source: .filesystemMTime) },
                reason: """
                Simulator runtime "\(runtime.name)" (\(runtime.identifier)) looks unused. \
                \(activitySummary) Reinstallable anytime from Xcode > Settings > Platforms.
                """
            ))
        }
        return items
    }
}

struct SimctlRuntimesResponse: Decodable, Sendable {
    let runtimes: [SimctlRuntime]
}

struct SimctlRuntime: Decodable, Sendable {
    let identifier: String
    let name: String
    let version: String?
    let runtimeRoot: String?
    let bundlePath: String?
    let isAvailable: Bool?
}

struct SimctlDevicesResponse: Decodable, Sendable {
    let devices: [String: [SimctlDevice]]
}

struct SimctlDevice: Decodable, Sendable {
    let udid: String
    let name: String?
    let state: String?
    let dataPath: String?
}
