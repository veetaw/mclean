import XCTest
@testable import PrivilegedHelperXPC

/// Exercises `MockPrivilegedHelper`'s in-memory simulation. None of these
/// tests touch real elevation, `SMAppService`, or XPC — they only verify the
/// mock's own documented, simplified rules.
final class MockPrivilegedHelperTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MockPrivilegedHelperTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        tempDirectory = nil
        try super.tearDownWithError()
    }

    private func makeTempFile(named name: String = "victim.txt") throws -> String {
        let url = tempDirectory.appendingPathComponent(name)
        try "test content".write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    // MARK: - helperVersion

    func testHelperVersionReturnsAFixedMockVersionString() async {
        let helper = MockPrivilegedHelper()
        let version = await helper.helperVersion()

        XCTAssertFalse(version.isEmpty)
        XCTAssertEqual(version, MockPrivilegedHelper.mockHelperVersion)
        // Should be self-evidently not a real helper version.
        XCTAssertTrue(version.lowercased().contains("mock"))
    }

    // MARK: - quarantinePath / restorePath round trip

    func testQuarantineThenRestoreRoundTripSucceeds() async throws {
        let helper = MockPrivilegedHelper()
        let path = try makeTempFile()
        let requestID = "req-\(UUID().uuidString)"

        let quarantineResult = await helper.quarantinePath(path, requestID: requestID)
        XCTAssertTrue(quarantineResult.success)
        XCTAssertNil(quarantineResult.errorDescription)

        let isQuarantined = await helper.isQuarantined(receiptID: requestID)
        XCTAssertTrue(isQuarantined)

        let restoreResult = await helper.restorePath(quarantineReceiptID: requestID)
        XCTAssertTrue(restoreResult.success)
        XCTAssertNil(restoreResult.errorDescription)

        let stillQuarantined = await helper.isQuarantined(receiptID: requestID)
        XCTAssertFalse(stillQuarantined)
    }

    func testRestoringTheSameReceiptTwiceFailsTheSecondTime() async throws {
        let helper = MockPrivilegedHelper()
        let path = try makeTempFile()
        let requestID = "req-\(UUID().uuidString)"

        _ = await helper.quarantinePath(path, requestID: requestID)
        let firstRestore = await helper.restorePath(quarantineReceiptID: requestID)
        XCTAssertTrue(firstRestore.success)

        let secondRestore = await helper.restorePath(quarantineReceiptID: requestID)
        XCTAssertFalse(secondRestore.success)
        XCTAssertNotNil(secondRestore.errorDescription)
    }

    func testRestoreOfAnUnknownReceiptIDFails() async {
        let helper = MockPrivilegedHelper()

        let result = await helper.restorePath(quarantineReceiptID: "never-issued-\(UUID().uuidString)")

        XCTAssertFalse(result.success)
        XCTAssertNotNil(result.errorDescription)
    }

    func testQuarantiningANonexistentPathFails() async {
        let helper = MockPrivilegedHelper()
        let missingPath = tempDirectory.appendingPathComponent("does-not-exist.txt").path

        let result = await helper.quarantinePath(missingPath, requestID: "req-\(UUID().uuidString)")

        XCTAssertFalse(result.success)
        XCTAssertNotNil(result.errorDescription)
    }

    func testQuarantiningAForbiddenPrefixFailsAndNeverRecordsIt() async {
        let helper = MockPrivilegedHelper()
        let requestID = "req-\(UUID().uuidString)"

        let result = await helper.quarantinePath("/System/Library/CoreServices", requestID: requestID)

        XCTAssertFalse(result.success)
        XCTAssertNotNil(result.errorDescription)

        let isQuarantined = await helper.isQuarantined(receiptID: requestID)
        XCTAssertFalse(isQuarantined)
    }

    func testQuarantiningEachHardcodedForbiddenPrefixFails() async throws {
        let helper = MockPrivilegedHelper()
        for prefix in MockPrivilegedHelper.forbiddenPathPrefixes {
            let result = await helper.quarantinePath(prefix, requestID: "req-\(UUID().uuidString)")
            XCTAssertFalse(result.success, "Expected \(prefix) to be forbidden")
        }
    }

    func testRestoringAfterAFailedQuarantineFindsNoReceipt() async {
        let helper = MockPrivilegedHelper()
        let requestID = "req-\(UUID().uuidString)"

        let quarantineResult = await helper.quarantinePath("/dev/null-ish-but-fake", requestID: requestID)
        XCTAssertFalse(quarantineResult.success)

        let restoreResult = await helper.restorePath(quarantineReceiptID: requestID)
        XCTAssertFalse(restoreResult.success)
    }

    // MARK: - runMaintenanceTask

    func testRecognizedMaintenanceTaskIDsSucceed() async {
        let helper = MockPrivilegedHelper()

        for taskID in MockPrivilegedHelper.recognizedMaintenanceTaskIDs {
            let result = await helper.runMaintenanceTask(taskID)
            XCTAssertTrue(result.success, "Expected \(taskID) to be recognized")
            XCTAssertFalse(result.output.isEmpty)
            XCTAssertNil(result.errorDescription)
        }
    }

    func testUnrecognizedMaintenanceTaskIDFails() async {
        let helper = MockPrivilegedHelper()

        let result = await helper.runMaintenanceTask("rm-rf-slash-please")

        XCTAssertFalse(result.success)
        XCTAssertNotNil(result.errorDescription)
    }

    // MARK: - Concurrency sanity

    func testConcurrentQuarantineCallsDoNotCorruptState() async throws {
        let helper = MockPrivilegedHelper()
        var paths: [String] = []
        for index in 0..<10 {
            paths.append(try makeTempFile(named: "victim-\(index).txt"))
        }

        await withTaskGroup(of: Void.self) { group in
            for (index, path) in paths.enumerated() {
                group.addTask {
                    _ = await helper.quarantinePath(path, requestID: "concurrent-\(index)")
                }
            }
        }

        for index in paths.indices {
            let isQuarantined = await helper.isQuarantined(receiptID: "concurrent-\(index)")
            XCTAssertTrue(isQuarantined)
        }
    }
}
