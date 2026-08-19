import CoreScanEngine
import Foundation
import SafetyRules
@testable import RemoteControlServer

final class FixtureScanSnapshotProvider: ScanSnapshotProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var _snapshot: ScanSnapshot

    init(snapshot: ScanSnapshot) {
        self._snapshot = snapshot
    }

    var snapshot: ScanSnapshot {
        get { lock.lock(); defer { lock.unlock() }; return _snapshot }
        set { lock.lock(); _snapshot = newValue; lock.unlock() }
    }

    func currentSnapshot() async -> ScanSnapshot {
        snapshot
    }
}

struct FixtureDiskSpaceProvider: DiskSpaceProviding {
    let status: DiskStatus
    func diskStatus() -> DiskStatus { status }
}

actor FixtureQuarantineManager: QuarantineManaging {
    private(set) var quarantinedItems: [ScanItem] = []
    var shouldThrow = false

    func quarantine(_ item: ScanItem, retention: QuarantinePolicy) async throws -> QuarantineReceipt {
        if shouldThrow {
            throw QuarantineError.underlying("fixture forced failure")
        }
        quarantinedItems.append(item)
        return QuarantineReceipt(
            originalPath: item.path,
            quarantinePath: "/tmp/fixture-quarantine/\(item.id.uuidString)",
            quarantinedAt: Date(),
            policy: retention,
            sourceItem: item
        )
    }

    func restore(_ receipt: QuarantineReceipt) async throws {}

    func purgeExpired() async throws -> [QuarantineReceipt] { [] }

    func listActive() async throws -> [QuarantineReceipt] { [] }
}

enum Fixture {
    static func needsConfirmationFinding(path: String = "/Users/tester/Downloads/big-file.zip") -> ScanFinding {
        let item = ScanItem(
            path: path,
            sizeBytes: 12_345,
            sourceDetectorID: "test.fixture",
            category: "Fixture",
            lastUsed: nil,
            reason: "Fixture item for tests"
        )
        return ScanFinding(item: item, verdict: .needsConfirmation(reason: "fixture"))
    }

    static func forbiddenFinding(path: String = "/System/Library/CoreServices") -> ScanFinding {
        let item = ScanItem(
            path: path,
            sizeBytes: 1,
            sourceDetectorID: "test.fixture",
            category: "Fixture",
            lastUsed: nil,
            reason: "Fixture forbidden item"
        )
        return ScanFinding(item: item, verdict: .forbidden(ruleID: "denylist.path", reason: "fixture"))
    }
}
