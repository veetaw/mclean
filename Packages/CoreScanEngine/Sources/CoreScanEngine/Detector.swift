import Foundation

/// Shared interface every module that *finds* things (DevToolsDetectors,
/// MobileDevDetectors, PowerUserInspectors, and the core System Junk / Large
/// & Old Files / Duplicate finders) implements.
///
/// A `Detector` only reads the filesystem/metadata and returns `ScanItem`s.
/// It MUST NOT delete, move, or modify anything — that separation is what
/// lets every detector run safely in dry-run mode by construction, and is
/// enforced by convention + code review, not by the type system alone.
public protocol Detector: Sendable {
    /// Stable, dotted identifier, e.g. "dev.node.node-modules-stale".
    var id: String { get }
    /// Human-readable name shown in scan results and settings.
    var displayName: String { get }
    /// Which top-level module this detector belongs to, for grouping in the UI
    /// and for `Capabilities` gating (e.g. disabled entirely in App Store build).
    var category: DetectorCategory { get }

    /// Run the detector. Always read-only. `context` carries concurrency
    /// limits and cancellation; detectors should check `Task.isCancelled`
    /// during long directory walks.
    func scan(context: ScanContext) async throws -> [ScanItem]
}

public enum DetectorCategory: String, Sendable, Codable, CaseIterable {
    case systemJunk
    case trash
    case largeAndOldFiles
    case duplicates
    case uninstaller
    case privacy
    case devTools
    case mobileDev
    case powerUser
}

/// Shared, read-only execution context passed to every detector.
public struct ScanContext: Sendable {
    /// Root(s) to scan; defaults to the current user's home directory plus
    /// well-known system locations relevant to the detector's category.
    public let roots: [String]
    /// Max concurrent filesystem operations this detector should use.
    public let maxConcurrency: Int
    /// Detectors must treat every scan as dry-run — there is currently no
    /// code path in CoreScanEngine that deletes anything. This flag exists so
    /// call sites are explicit about intent even before deletion exists.
    public let dryRun: Bool

    public init(roots: [String], maxConcurrency: Int = 4, dryRun: Bool = true) {
        self.roots = roots
        self.maxConcurrency = maxConcurrency
        self.dryRun = dryRun
    }
}
