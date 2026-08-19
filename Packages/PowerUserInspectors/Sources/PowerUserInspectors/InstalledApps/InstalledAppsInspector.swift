import Foundation
import CoreScanEngine

/// Enumerates installed applications under `/Applications` and
/// `~/Applications`, reporting bundle ID, version, recursive size on disk,
/// and a best-effort last-used date. Strictly read-only.
public struct InstalledAppsInspector: Sendable {
    private let lastUsedProvider: AppLastUsedDateProviding

    public init(lastUsedProvider: AppLastUsedDateProviding = MDLSLastUsedDateProvider()) {
        self.lastUsedProvider = lastUsedProvider
    }

    /// `/Applications` and `~/Applications` — the two conventional
    /// locations apps install to on macOS. Callers running against a test
    /// fixture pass an explicit list instead.
    public static func defaultSearchDirectories(homeDirectory: String = NSHomeDirectory()) -> [String] {
        ["/Applications", homeDirectory + "/Applications"]
    }

    /// Scans every `.app` bundle directly under each of `directories`
    /// (non-recursive — nested `.app` bundles inside another app's
    /// `Contents/` are that app's implementation detail, not a separately
    /// installed application). Duplicate bundle paths across directories are
    /// only reported once. Returns entries sorted by display name.
    public func scanApplications(
        in directories: [String] = InstalledAppsInspector.defaultSearchDirectories()
    ) async -> [InstalledApp] {
        var apps: [InstalledApp] = []
        var seenPaths = Set<String>()
        for directory in directories {
            guard PowerUserFS.isDirectory(directory) else { continue }
            for entry in PowerUserFS.directoryEntries(directory) where entry.hasSuffix(".app") {
                let bundlePath = directory + "/" + entry
                guard seenPaths.insert(bundlePath).inserted else { continue }
                if let app = await inspectBundle(at: bundlePath) {
                    apps.append(app)
                }
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func inspectBundle(at bundlePath: String) async -> InstalledApp? {
        guard PowerUserFS.isDirectory(bundlePath) else { return nil }

        let info = Self.readInfoPlist(at: bundlePath + "/Contents/Info.plist")
        let fallbackName = URL(fileURLWithPath: bundlePath).deletingPathExtension().lastPathComponent
        let name = (info?["CFBundleName"] as? String)
            ?? (info?["CFBundleDisplayName"] as? String)
            ?? fallbackName
        let bundleIdentifier = info?["CFBundleIdentifier"] as? String
        let shortVersion = info?["CFBundleShortVersionString"] as? String
        let buildVersion = info?["CFBundleVersion"] as? String
        let sizeBytes = PowerUserFS.recursiveSize(of: bundlePath)
        let lastUsed = await lastUsedProvider.lastUsedDate(forBundlePath: bundlePath)
            .map { LastUsedEvidence(date: $0, source: .spotlightLastUsedDate) }

        return InstalledApp(
            name: name,
            bundleIdentifier: bundleIdentifier,
            shortVersion: shortVersion,
            buildVersion: buildVersion,
            path: bundlePath,
            sizeBytes: sizeBytes,
            lastUsed: lastUsed
        )
    }

    static func readInfoPlist(at path: String) -> [String: Any]? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
    }
}
