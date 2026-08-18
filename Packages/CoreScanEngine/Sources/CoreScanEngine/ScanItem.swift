import Foundation

/// A single filesystem artifact discovered by a `Detector` (a cache directory,
/// a stray `node_modules`, a large old file, a duplicate photo, ...).
///
/// `ScanItem` is a pure data value — it never performs I/O and never deletes
/// anything. Detectors produce these; `SafetyRules` classifies them; the UI
/// and `RemoteControlServer` present them; only an explicit, user-confirmed
/// action (outside this type) ever touches disk.
public struct ScanItem: Sendable, Identifiable, Hashable, Codable {
    public let id: UUID
    /// Absolute filesystem path of the artifact.
    public let path: String
    /// Size on disk, in bytes. `nil` if not yet computed (e.g. large directory
    /// trees may report this lazily/asynchronously).
    public let sizeBytes: Int64?
    /// Which detector/category produced this item, e.g. "dev.python.pip-cache".
    public let sourceDetectorID: String
    /// Human-readable category shown in the UI, e.g. "Python — pip cache".
    public let category: String
    /// Best-effort "last real use" signal — see `LastUsedEvidence`.
    public let lastUsed: LastUsedEvidence?
    /// Free-form, human-readable justification for why this item was flagged.
    public let reason: String

    public init(
        id: UUID = UUID(),
        path: String,
        sizeBytes: Int64?,
        sourceDetectorID: String,
        category: String,
        lastUsed: LastUsedEvidence?,
        reason: String
    ) {
        self.id = id
        self.path = path
        self.sizeBytes = sizeBytes
        self.sourceDetectorID = sourceDetectorID
        self.category = category
        self.lastUsed = lastUsed
        self.reason = reason
    }
}

/// Evidence used to estimate when an artifact was last *actually used*, as
/// opposed to merely `mtime`, which is easily misleading (e.g. a tarball
/// extraction touches every file's mtime without anyone "using" them).
///
/// Detectors should prefer the strongest evidence available and record which
/// one they used, so the UI can show its confidence honestly.
public struct LastUsedEvidence: Sendable, Hashable, Codable {
    public enum Source: String, Sendable, Codable {
        /// `kMDItemLastUsedDate` via Spotlight metadata (`mdls`/`NSMetadataItem`).
        case spotlightLastUsedDate
        /// mtime of a lockfile/manifest that is authoritative for "last build".
        case manifestOrLockfileMTime
        /// Filesystem mtime of the artifact itself — weakest signal.
        case filesystemMTime
        /// Correlated against recent shell history (only when accessible/opted-in).
        case shellHistoryCorrelation
    }

    public let date: Date
    public let source: Source

    public init(date: Date, source: Source) {
        self.date = date
        self.source = source
    }
}
