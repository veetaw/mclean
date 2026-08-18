import Foundation
import CoreScanEngine

/// Finds Xcode developer artifacts:
/// - `DerivedData` (build intermediates/indexes, per project)
/// - old `.xcarchive` archives
/// - downloaded Simulator runtimes
/// - old iOS/watchOS/tvOS "DeviceSupport" folders (per-OS-version debug
///   symbols downloaded for on-device debugging)
///
/// Strictly read-only. See `CoreScanEngine.Detector`.
public struct XcodeDetector: Detector {
    public let id = "dev.xcode"
    public let displayName = "Xcode"
    public let category: DetectorCategory = .devTools

    private let staleDerivedDataThreshold: TimeInterval
    private let staleArchiveThreshold: TimeInterval
    private let staleDeviceSupportThreshold: TimeInterval
    private let now: @Sendable () -> Date

    public init(
        staleDerivedDataThreshold: TimeInterval = 30 * 24 * 3600,
        staleArchiveThreshold: TimeInterval = 180 * 24 * 3600,
        staleDeviceSupportThreshold: TimeInterval = 180 * 24 * 3600,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.staleDerivedDataThreshold = staleDerivedDataThreshold
        self.staleArchiveThreshold = staleArchiveThreshold
        self.staleDeviceSupportThreshold = staleDeviceSupportThreshold
        self.now = now
    }

    public func scan(context: ScanContext) async throws -> [ScanItem] {
        var items: [ScanItem] = []
        for home in HomeDirectories.resolve(context) {
            if Task.isCancelled { break }
            items.append(contentsOf: scanDerivedData(home: home))
            items.append(contentsOf: scanArchives(home: home))
            items.append(contentsOf: scanSimulatorRuntimes(home: home))
            items.append(contentsOf: scanDeviceSupport(home: home))
        }
        return items
    }

    private func scanDerivedData(home: String) -> [ScanItem] {
        let root = home + "/Library/Developer/Xcode/DerivedData"
        guard DevToolsFS.isDirectory(root) else { return [] }

        var items: [ScanItem] = []
        for entry in DevToolsFS.directoryEntries(root) {
            let path = root + "/" + entry
            guard DevToolsFS.isDirectory(path) else { continue }
            let mtime = DevToolsFS.modificationDate(path)
            let isStale = mtime.map { now().timeIntervalSince($0) >= staleDerivedDataThreshold } ?? false
            items.append(ScanItem(
                path: path,
                sizeBytes: DevToolsFS.recursiveSize(of: path, isCancelled: { Task.isCancelled }),
                sourceDetectorID: "dev.xcode.derived-data",
                category: "Xcode — DerivedData",
                lastUsed: mtime.map { LastUsedEvidence(date: $0, source: .filesystemMTime) },
                reason: isStale
                    ? "Build intermediates and indexes for project '\(entry)', untouched for \(daysText(staleDerivedDataThreshold)). Xcode regenerates DerivedData automatically on the next build/open."
                    : "Build intermediates and indexes for project '\(entry)'. Xcode regenerates DerivedData automatically on the next build/open; safe to clear anytime, though a recently active project pays a full-rebuild cost."
            ))
        }
        return items
    }

    private func scanArchives(home: String) -> [ScanItem] {
        let root = home + "/Library/Developer/Xcode/Archives"
        guard DevToolsFS.isDirectory(root) else { return [] }

        var items: [ScanItem] = []
        for dateFolder in DevToolsFS.directoryEntries(root) {
            let dateFolderPath = root + "/" + dateFolder
            guard DevToolsFS.isDirectory(dateFolderPath) else { continue }
            for archive in DevToolsFS.directoryEntries(dateFolderPath) {
                let archivePath = dateFolderPath + "/" + archive
                guard let mtime = DevToolsFS.modificationDate(archivePath),
                      now().timeIntervalSince(mtime) >= staleArchiveThreshold else { continue }
                items.append(ScanItem(
                    path: archivePath,
                    sizeBytes: DevToolsFS.recursiveSize(of: archivePath, isCancelled: { Task.isCancelled }),
                    sourceDetectorID: "dev.xcode.old-archive",
                    category: "Xcode — old archive",
                    lastUsed: LastUsedEvidence(date: mtime, source: .filesystemMTime),
                    reason: "App Store/TestFlight archive '\(archive)', created \(daysText(staleArchiveThreshold)) ago. Needed to re-submit that exact build or symbolicate its crash logs — confirm you no longer need either before removing."
                ))
            }
        }
        return items
    }

    private func scanSimulatorRuntimes(home: String) -> [ScanItem] {
        let root = home + "/Library/Developer/CoreSimulator/Profiles/Runtimes"
        guard DevToolsFS.isDirectory(root) else { return [] }

        var items: [ScanItem] = []
        for entry in DevToolsFS.directoryEntries(root) {
            let path = root + "/" + entry
            items.append(ScanItem(
                path: path,
                sizeBytes: DevToolsFS.recursiveSize(of: path, isCancelled: { Task.isCancelled }),
                sourceDetectorID: "dev.xcode.simulator-runtime",
                category: "Xcode — Simulator runtime",
                lastUsed: DevToolsFS.modificationDate(path).map { LastUsedEvidence(date: $0, source: .filesystemMTime) },
                reason: "Downloaded Simulator runtime image '\(entry)'. This detector cannot see which runtimes have simulators booted against them (best-effort by mtime only) — check Xcode > Settings > Platforms before removing; re-downloadable there if needed again."
            ))
        }
        return items
    }

    private func scanDeviceSupport(home: String) -> [ScanItem] {
        let roots = [
            home + "/Library/Developer/Xcode/iOS DeviceSupport",
            home + "/Library/Developer/Xcode/watchOS DeviceSupport",
            home + "/Library/Developer/Xcode/tvOS DeviceSupport"
        ]

        var items: [ScanItem] = []
        for root in roots {
            guard DevToolsFS.isDirectory(root) else { continue }
            for entry in DevToolsFS.directoryEntries(root) {
                let path = root + "/" + entry
                guard let mtime = DevToolsFS.modificationDate(path),
                      now().timeIntervalSince(mtime) >= staleDeviceSupportThreshold else { continue }
                items.append(ScanItem(
                    path: path,
                    sizeBytes: DevToolsFS.recursiveSize(of: path, isCancelled: { Task.isCancelled }),
                    sourceDetectorID: "dev.xcode.device-support",
                    category: "Xcode — device support files",
                    lastUsed: LastUsedEvidence(date: mtime, source: .filesystemMTime),
                    reason: "Debug symbols for OS/device build '\(entry)', untouched for \(daysText(staleDeviceSupportThreshold)). Re-downloaded automatically the next time you debug on a device running that OS version."
                ))
            }
        }
        return items
    }
}
