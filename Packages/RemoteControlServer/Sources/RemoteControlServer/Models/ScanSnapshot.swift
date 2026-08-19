import CoreScanEngine
import Foundation
import SafetyRules

/// Supplies the "current" scan results to `RemoteControlServer`. This
/// package never runs a scan itself — `ScanEngine` (in `CoreScanEngine`)
/// and `SafetyClassifying` (in `SafetyRules`) already own that pipeline on
/// the desktop side. `RemoteControlServer` only ever reflects whatever
/// snapshot the desktop app hands it through this protocol.
///
/// A typical desktop-side conformer wraps the app's own scan-result cache
/// and updates it after each `ScanEngine.runAll(context:)` completes.
public protocol ScanSnapshotProviding: Sendable {
    func currentSnapshot() async -> ScanSnapshot
}

/// A point-in-time view of the last completed scan, already classified.
public struct ScanSnapshot: Sendable, Codable, Equatable {
    public let lastScanStartedAt: Date?
    public let lastScanFinishedAt: Date?
    public let findings: [ScanFinding]

    public init(lastScanStartedAt: Date?, lastScanFinishedAt: Date?, findings: [ScanFinding]) {
        self.lastScanStartedAt = lastScanStartedAt
        self.lastScanFinishedAt = lastScanFinishedAt
        self.findings = findings
    }

    /// The state before any scan has ever completed.
    public static let empty = ScanSnapshot(lastScanStartedAt: nil, lastScanFinishedAt: nil, findings: [])
}

/// One `ScanItem` paired with the `SafetyVerdict` `SafetyRules` already
/// assigned it. `RemoteControlServer` never re-classifies and never
/// classifies on its own — it only ever displays/relays a verdict that was
/// already computed by `SafetyRules.SafetyClassifying`, matching the
/// three-tier vocabulary in `SAFETY_RULES.md` (forbidden / safe-auto /
/// needs-confirmation).
public struct ScanFinding: Sendable, Codable, Identifiable, Equatable {
    public let item: ScanItem
    public let verdict: SafetyVerdict

    public var id: UUID { item.id }

    public init(item: ScanItem, verdict: SafetyVerdict) {
        self.item = item
        self.verdict = verdict
    }
}
