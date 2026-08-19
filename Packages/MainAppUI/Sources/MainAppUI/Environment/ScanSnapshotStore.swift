import CoreScanEngine
import Foundation
import RemoteControlServer
import SafetyRules

/// The desktop app's own conformer of `RemoteControlServer.ScanSnapshotProviding`
/// (see that protocol's doc comment: `RemoteControlServer` never scans or
/// classifies on its own — it only ever reflects whatever snapshot the
/// desktop app hands it). `AppEnvironment` owns one instance and calls
/// `record(startedAt:finishedAt:findings:)` after every scan it runs and
/// classifies; the same snapshot backs both the SwiftUI findings views and
/// (when running) the LAN remote-control API, so the two surfaces never
/// diverge.
public actor ScanSnapshotStore: ScanSnapshotProviding {
    private var snapshot: ScanSnapshot = .empty

    public init() {}

    public func currentSnapshot() async -> ScanSnapshot {
        snapshot
    }

    public func record(startedAt: Date, finishedAt: Date, findings: [ScanFinding]) {
        snapshot = ScanSnapshot(lastScanStartedAt: startedAt, lastScanFinishedAt: finishedAt, findings: findings)
    }
}
