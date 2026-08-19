import Foundation

/// A single installed package/module/formula, as reported by one language
/// ecosystem's own listing command. Read-only inventory data — this package
/// never installs or uninstalls anything.
public struct PackageEntry: Sendable, Hashable, Codable, Identifiable {
    public let id: UUID
    public let ecosystem: PackageEcosystem
    public let name: String
    public let version: String
    /// Best-effort size on disk, in bytes. `nil` when computing it would
    /// require an extra, non-trivial lookup this package deliberately
    /// avoids doing per-package (e.g. gem's install layout varies too much
    /// across system/rbenv/rvm/chruby Rubies to guess reliably).
    public let sizeBytes: Int64?
    /// Best-effort last-access signal. In practice this is usually a
    /// filesystem modification time on the package's install directory —
    /// a weak signal (see `CoreScanEngine.LastUsedEvidence` for the same
    /// caveat elsewhere in this codebase), not true "last imported/run".
    public let lastAccessed: Date?
    public let installPath: String?

    public init(
        id: UUID = UUID(),
        ecosystem: PackageEcosystem,
        name: String,
        version: String,
        sizeBytes: Int64? = nil,
        lastAccessed: Date? = nil,
        installPath: String? = nil
    ) {
        self.id = id
        self.ecosystem = ecosystem
        self.name = name
        self.version = version
        self.sizeBytes = sizeBytes
        self.lastAccessed = lastAccessed
        self.installPath = installPath
    }
}

public enum PackageEcosystem: String, Sendable, Codable, CaseIterable {
    case pip
    case npm
    case cargo
    case gem
    case goModules
    case homebrew
}
