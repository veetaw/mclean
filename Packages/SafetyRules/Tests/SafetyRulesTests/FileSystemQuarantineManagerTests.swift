import CoreScanEngine
import XCTest
@testable import SafetyRules

final class FileSystemQuarantineManagerTests: XCTestCase {
    private var tempRoot: URL!
    private var quarantineRoot: URL!
    private var manager: FileSystemQuarantineManager!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("MCleanProTests-\(UUID().uuidString)", isDirectory: true)
        quarantineRoot = tempRoot.appendingPathComponent("Quarantine", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        manager = FileSystemQuarantineManager(quarantineRootURL: quarantineRoot)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
        try super.tearDownWithError()
    }

    private func makeTestFile(named name: String, contents: String = "hello") throws -> URL {
        let url = tempRoot.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testQuarantineMovesFileAndReturnsReceipt() async throws {
        let fileURL = try makeTestFile(named: "sample.txt")
        let item = ScanItemFixture.make(path: fileURL.path)

        let receipt = try await manager.quarantine(item, retention: .default)

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path), "original should be moved away")
        XCTAssertTrue(FileManager.default.fileExists(atPath: receipt.quarantinePath))
        XCTAssertEqual(receipt.originalPath, fileURL.path)
    }

    func testQuarantineRefusesForbiddenPath() async {
        let item = ScanItemFixture.make(path: "/System/Library/CoreServices/Foo")
        do {
            _ = try await manager.quarantine(item, retention: .default)
            XCTFail("Expected quarantine to throw for a forbidden path")
        } catch let error as QuarantineError {
            guard case .pathForbidden = error else {
                return XCTFail("Expected .pathForbidden, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testQuarantineThenRestoreRoundTrips() async throws {
        let fileURL = try makeTestFile(named: "restore-me.txt", contents: "round trip")
        let item = ScanItemFixture.make(path: fileURL.path)

        let receipt = try await manager.quarantine(item, retention: .default)
        try await manager.restore(receipt)

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertEqual(contents, "round trip")

        let active = try await manager.listActive()
        XCTAssertTrue(active.isEmpty)
    }

    func testRestoreRefusesToClobberExistingFile() async throws {
        let fileURL = try makeTestFile(named: "clobber.txt")
        let item = ScanItemFixture.make(path: fileURL.path)
        let receipt = try await manager.quarantine(item, retention: .default)

        // Something now occupies the original path again.
        try "new content".write(to: fileURL, atomically: true, encoding: .utf8)

        do {
            try await manager.restore(receipt)
            XCTFail("Expected restore to refuse clobbering an occupied destination")
        } catch let error as QuarantineError {
            guard case .restoreDestinationOccupied = error else {
                return XCTFail("Expected .restoreDestinationOccupied, got \(error)")
            }
        }
    }

    func testPurgeExpiredOnlyRemovesElapsedRetention() async throws {
        let freshURL = try makeTestFile(named: "fresh.txt")
        let staleURL = try makeTestFile(named: "stale.txt")

        let freshReceipt = try await manager.quarantine(
            ScanItemFixture.make(path: freshURL.path),
            retention: QuarantinePolicy(retentionDays: 7)
        )
        // Simulate an item quarantined far enough in the past that a
        // 0-day retention policy has already elapsed.
        let staleReceipt = try await manager.quarantine(
            ScanItemFixture.make(path: staleURL.path),
            retention: QuarantinePolicy(retentionDays: 0)
        )

        let purged = try await manager.purgeExpired()

        XCTAssertEqual(purged.map(\.id), [staleReceipt.id])
        let stillActive = try await manager.listActive()
        XCTAssertEqual(stillActive.map(\.id), [freshReceipt.id])
        XCTAssertFalse(FileManager.default.fileExists(atPath: staleReceipt.quarantinePath))
    }

    func testListActiveReflectsManifestAcrossManagerInstances() async throws {
        let fileURL = try makeTestFile(named: "persisted.txt")
        let item = ScanItemFixture.make(path: fileURL.path)
        _ = try await manager.quarantine(item, retention: .default)

        // A fresh manager instance pointed at the same root should see the
        // same manifest — this exercises the on-disk persistence, not just
        // in-memory state.
        let secondManager = FileSystemQuarantineManager(quarantineRootURL: quarantineRoot)
        let active = try await secondManager.listActive()
        XCTAssertEqual(active.count, 1)
        XCTAssertEqual(active.first?.originalPath, fileURL.path)
    }
}
