import Foundation
import CoreScanEngine

/// Flags Android Virtual Device (emulator) images under `~/.android/avd`
/// that show no sign of having been launched recently.
///
/// AVD "last launched" is *not* reliably recorded anywhere on disk — there
/// is no launch log. The best available proxy is the mtime of the files an
/// actual emulator boot rewrites (the userdata disk image, snapshot state),
/// falling back to the `.avd` directory's own mtime. This detector is
/// explicit about that weakness in `reason` rather than presenting it as an
/// authoritative "last used" date.
public struct AndroidAVDDetector: Detector {
    public let id = "mobile.android.avd-stale"
    public let displayName = "Android — unused emulator (AVD) images"
    public let category: DetectorCategory = .mobileDev

    private let avdRootPath: String
    private let staleThresholdDays: Int

    /// - Parameters:
    ///   - avdRootPath: Directory containing `*.avd` subdirectories.
    ///     Defaults to `~/.android/avd`; overridable for tests.
    ///   - staleThresholdDays: Minimum inferred inactivity, in days, before
    ///     an AVD is flagged.
    public init(
        avdRootPath: String = FSUtil.homeDirectory() + "/.android/avd",
        staleThresholdDays: Int = 60
    ) {
        self.avdRootPath = avdRootPath
        self.staleThresholdDays = staleThresholdDays
    }

    public func scan(context: ScanContext) async throws -> [ScanItem] {
        guard FSUtil.exists(atPath: avdRootPath, isDirectory: true) else { return [] }

        let root = URL(fileURLWithPath: avdRootPath)
        let avdDirs = FSUtil.subdirectories(of: root).filter { $0.pathExtension == "avd" }
        guard !avdDirs.isEmpty else { return [] }

        try Task.checkCancellation()
        let sizes = await FSUtil.sizes(of: avdDirs, maxConcurrency: context.maxConcurrency)

        let now = Date()
        let cutoff = Calendar.current.date(byAdding: .day, value: -staleThresholdDays, to: now) ?? .distantPast

        var items: [ScanItem] = []
        for avdDir in avdDirs {
            try Task.checkCancellation()

            let name = avdDir.deletingPathExtension().lastPathComponent
            let runtimeSignals = [
                avdDir.appendingPathComponent("userdata-qemu.img").path,
                avdDir.appendingPathComponent("userdata.img").path,
                avdDir.appendingPathComponent("snapshots").path
            ]

            let lastUsedDate = FSUtil.latestModificationDate(among: runtimeSignals)
                ?? FSUtil.modificationDate(ofItemAt: avdDir.path)
            guard let lastUsedDate, lastUsedDate < cutoff else { continue }

            let daysAgo = max(0, Int(now.timeIntervalSince(lastUsedDate) / 86_400))
            items.append(ScanItem(
                path: avdDir.path,
                sizeBytes: sizes[avdDir],
                sourceDetectorID: id,
                category: "Android — AVD emulator image",
                lastUsed: LastUsedEvidence(date: lastUsedDate, source: .filesystemMTime),
                reason: """
                Emulator image "\(name)" shows no filesystem activity (userdata image, \
                snapshots, or directory mtime) in ~\(daysAgo) days. Note: AVD "last \
                launched" isn't reliably recorded on disk, so this is a best-effort \
                proxy, not an authoritative launch log.
                """
            ))
        }
        return items
    }
}
