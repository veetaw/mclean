import Foundation

/// Produces a JSON "system report": installed-apps summary, disk usage, and
/// installed-package counts per language ecosystem.
///
/// **PDF export is a documented stub, not implemented here.** Rendering a
/// PDF is a UI-layer concern — `SwiftUI.ImageRenderer` or the AppKit print
/// APIs, which need an actual view hierarchy to render — not something this
/// data-layer package should own, and there's no `MainAppUI` target yet to
/// host that view. `exportPDF()` exists only so the intended call site is
/// documented; it always throws `SystemReportError.pdfExportNotImplemented`.
/// TODO: once `MainAppUI` exists, build PDF export there from the
/// `SystemReport` this type already produces.
public struct SystemReportExporter: Sendable {
    private let appsInspector: InstalledAppsInspector
    private let packageExplorer: PackageExplorer

    public init(
        appsInspector: InstalledAppsInspector = InstalledAppsInspector(),
        packageExplorer: PackageExplorer = PackageExplorer()
    ) {
        self.appsInspector = appsInspector
        self.packageExplorer = packageExplorer
    }

    public func buildReport(
        applicationDirectories: [String] = InstalledAppsInspector.defaultSearchDirectories(),
        goModuleDirectory: String? = nil,
        volumePath: String = "/"
    ) async -> SystemReport {
        async let appsTask = appsInspector.scanApplications(in: applicationDirectories)
        async let packagesTask = packageExplorer.listAll(goModuleDirectory: goModuleDirectory)
        let apps = await appsTask
        let packagesByEcosystem = await packagesTask

        let totalAppsSizeBytes = apps.reduce(Int64(0)) { $0 + ($1.sizeBytes ?? 0) }
        var packageCounts: [String: Int] = [:]
        for (ecosystem, entries) in packagesByEcosystem {
            packageCounts[ecosystem.rawValue] = entries.count
        }

        return SystemReport(
            generatedAt: Date(),
            installedApps: apps.map {
                InstalledAppSummary(
                    name: $0.name,
                    bundleIdentifier: $0.bundleIdentifier,
                    version: $0.shortVersion,
                    sizeBytes: $0.sizeBytes
                )
            },
            totalAppsSizeBytes: totalAppsSizeBytes,
            diskUsage: Self.diskUsage(atPath: volumePath),
            packageCounts: packageCounts
        )
    }

    /// Encodes `buildReport(...)`'s result as pretty-printed, key-sorted
    /// JSON (stable diffs across runs), with ISO-8601 dates.
    public func exportJSON(
        applicationDirectories: [String] = InstalledAppsInspector.defaultSearchDirectories(),
        goModuleDirectory: String? = nil,
        volumePath: String = "/"
    ) async throws -> Data {
        let report = await buildReport(
            applicationDirectories: applicationDirectories,
            goModuleDirectory: goModuleDirectory,
            volumePath: volumePath
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(report)
    }

    /// Always throws — see the type doc comment. PDF rendering belongs in
    /// the (not-yet-scaffolded) `MainAppUI` target.
    public func exportPDF() throws -> Data {
        throw SystemReportError.pdfExportNotImplemented
    }

    private static func diskUsage(atPath path: String) -> DiskUsageSummary {
        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: path) else {
            return DiskUsageSummary(volumeTotalBytes: nil, volumeAvailableBytes: nil)
        }
        return DiskUsageSummary(
            volumeTotalBytes: (attributes[.systemSize] as? NSNumber)?.int64Value,
            volumeAvailableBytes: (attributes[.systemFreeSize] as? NSNumber)?.int64Value
        )
    }
}

public struct SystemReport: Sendable, Codable, Equatable {
    public let generatedAt: Date
    public let installedApps: [InstalledAppSummary]
    public let totalAppsSizeBytes: Int64
    public let diskUsage: DiskUsageSummary
    /// `PackageEcosystem.rawValue` -> installed package count.
    public let packageCounts: [String: Int]
}

public struct InstalledAppSummary: Sendable, Codable, Equatable {
    public let name: String
    public let bundleIdentifier: String?
    public let version: String?
    public let sizeBytes: Int64?
}

public struct DiskUsageSummary: Sendable, Codable, Equatable {
    public let volumeTotalBytes: Int64?
    public let volumeAvailableBytes: Int64?
}

public enum SystemReportError: Error, Sendable, Equatable {
    /// See the `SystemReportExporter` doc comment: PDF export is a
    /// deliberate, documented TODO for the future UI layer, not a bug.
    case pdfExportNotImplemented
}
