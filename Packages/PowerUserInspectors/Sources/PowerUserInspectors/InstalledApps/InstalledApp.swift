import Foundation
import CoreScanEngine

/// A single application bundle discovered under `/Applications` or
/// `~/Applications` by `InstalledAppsInspector` — plain inventory data, not
/// a "cleanable item" (see `InstalledAppsDetector` for the `Detector`
/// adapter that wraps this for the shared scan pipeline).
public struct InstalledApp: Sendable, Hashable, Codable, Identifiable {
    public let id: UUID
    /// `CFBundleName`/`CFBundleDisplayName` from `Info.plist`, falling back
    /// to the `.app` bundle's filename (without extension) if neither key
    /// is present.
    public let name: String
    public let bundleIdentifier: String?
    /// `CFBundleShortVersionString` (the user-facing "1.2.3" version).
    public let shortVersion: String?
    /// `CFBundleVersion` (the build number, often more granular than
    /// `shortVersion`).
    public let buildVersion: String?
    /// Absolute path to the `.app` bundle.
    public let path: String
    /// Recursive size on disk, in bytes. `nil` only if the bundle
    /// disappeared between being listed and being measured.
    public let sizeBytes: Int64?
    /// Best-effort last-used signal — see `AppLastUsedDateProviding`.
    /// `nil` when Spotlight has no `kMDItemLastUsedDate` for this bundle
    /// (unindexed volume, Spotlight disabled, never launched, sandboxed
    /// test fixture, ...) — this is expected to be common, not an error.
    public let lastUsed: LastUsedEvidence?

    public init(
        id: UUID = UUID(),
        name: String,
        bundleIdentifier: String?,
        shortVersion: String?,
        buildVersion: String?,
        path: String,
        sizeBytes: Int64?,
        lastUsed: LastUsedEvidence?
    ) {
        self.id = id
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.shortVersion = shortVersion
        self.buildVersion = buildVersion
        self.path = path
        self.sizeBytes = sizeBytes
        self.lastUsed = lastUsed
    }
}
