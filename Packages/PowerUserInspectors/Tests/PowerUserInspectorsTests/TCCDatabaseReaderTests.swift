import XCTest
@testable import PowerUserInspectors

final class TCCDatabaseReaderTests: TempDirTestCase {
    private func makeDatabaseFile() throws -> URL {
        let dbPath = tempDir.appendingPathComponent("TCC.db")
        try TestSupport.makeFile(at: dbPath, contents: "not a real sqlite file, just needs to exist")
        return dbPath
    }

    func testReadGrantsReturnsUnavailableWhenDatabaseFileMissing() async {
        let missingPath = tempDir.appendingPathComponent("TCC.db").path
        let reader = TCCDatabaseReader(databasePath: missingPath, commandRunner: FakeCommandRunner())

        let result = await reader.readGrants(forClientIdentifier: nil)

        XCTAssertEqual(result, .unavailable(reason: .databaseNotFound))
    }

    func testReadGrantsParsesModernSchemaAndMapsAuthorizationValues() async throws {
        let dbPath = try makeDatabaseFile()
        let sample = """
        [
          {"client": "com.apple.Terminal", "service": "kTCCServiceCamera", "auth_value": 2, "last_modified": 1700000000},
          {"client": "com.example.App", "service": "kTCCServiceMicrophone", "auth_value": 0, "last_modified": 1700000100},
          {"client": "com.example.App2", "service": "kTCCServicePhotos", "auth_value": 3, "last_modified": 1700000200}
        ]
        """
        let runner = FakeCommandRunner(resultsByExecutable: ["/usr/bin/sqlite3": makeResult(sample)])
        let reader = TCCDatabaseReader(databasePath: dbPath.path, commandRunner: runner)

        let result = await reader.readGrants(forClientIdentifier: nil)

        guard case .grants(let grants) = result else {
            return XCTFail("expected .grants, got \(result)")
        }
        XCTAssertEqual(grants.count, 3)
        XCTAssertEqual(grants.first { $0.clientIdentifier == "com.apple.Terminal" }?.authorizationValue, .allowed)
        XCTAssertEqual(grants.first { $0.clientIdentifier == "com.example.App" }?.authorizationValue, .denied)
        XCTAssertEqual(grants.first { $0.clientIdentifier == "com.example.App2" }?.authorizationValue, .limited)
        XCTAssertEqual(grants.first { $0.clientIdentifier == "com.apple.Terminal" }?.service, .camera)
    }

    func testReadGrantsFallsBackToLegacySchemaWhenModernColumnMissing() async throws {
        let dbPath = try makeDatabaseFile()
        // Modern query fails (simulates "no such column: auth_value" on an
        // old TCC.db); legacy query succeeds. `LegacyFallbackRunner`
        // distinguishes the two by which column name appears in the SQL.
        let reader = TCCDatabaseReader(databasePath: dbPath.path, commandRunner: LegacyFallbackRunner())

        let result = await reader.readGrants(forClientIdentifier: nil)

        guard case .grants(let grants) = result else {
            return XCTFail("expected .grants, got \(result)")
        }
        XCTAssertEqual(grants.count, 1)
        XCTAssertEqual(grants.first?.authorizationValue, .allowed)
    }

    func testReadGrantsWithEmptyResultSetReturnsEmptyGrants() async throws {
        let dbPath = try makeDatabaseFile()
        let runner = FakeCommandRunner(resultsByExecutable: ["/usr/bin/sqlite3": makeResult("")])
        let reader = TCCDatabaseReader(databasePath: dbPath.path, commandRunner: runner)

        let result = await reader.readGrants(forClientIdentifier: nil)

        XCTAssertEqual(result, .grants([]))
    }

    func testReadGrantsFiltersByClientIdentifierInQuery() async throws {
        let dbPath = try makeDatabaseFile()
        let runner = FakeCommandRunner(resultsByExecutable: [
            "/usr/bin/sqlite3": makeResult(#"[{"client": "com.example.App", "service": "kTCCServiceCamera", "auth_value": 2, "last_modified": 1700000000}]"#)
        ])
        let reader = TCCDatabaseReader(databasePath: dbPath.path, commandRunner: runner)

        _ = await reader.readGrants(forClientIdentifier: "com.example.App")

        let invocations = await runner.invocations
        let sql = invocations.first?.arguments.last ?? ""
        XCTAssertTrue(sql.contains("WHERE client = 'com.example.App'"))
    }

    func testReadGrantsReturnsFullDiskAccessRequiredWhenQueryFailsButSqlite3Exists() async throws {
        let dbPath = try makeDatabaseFile()
        // A real, executable file stands in for /usr/bin/sqlite3 so the
        // reader's "is the tool installed" check passes, isolating the
        // "query failed" (permission) branch.
        let fakeSqlite3 = tempDir.appendingPathComponent("fake-sqlite3")
        try TestSupport.makeFile(at: fakeSqlite3, contents: "#!/bin/sh\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeSqlite3.path)

        let runner = FakeCommandRunner(resultsByExecutable: [
            fakeSqlite3.path: makeResult("", exitCode: 1, stderr: "unable to open database file")
        ])
        let reader = TCCDatabaseReader(databasePath: dbPath.path, commandRunner: runner, sqlite3Path: fakeSqlite3.path)

        let result = await reader.readGrants(forClientIdentifier: nil)

        XCTAssertEqual(result, .unavailable(reason: .fullDiskAccessRequired))
    }

    func testReadGrantsReturnsQueryToolUnavailableWhenSqlite3BinaryDoesNotExist() async throws {
        let dbPath = try makeDatabaseFile()
        let nonexistentSqlite3 = tempDir.appendingPathComponent("no-such-binary").path
        let reader = TCCDatabaseReader(databasePath: dbPath.path, commandRunner: FakeCommandRunner(), sqlite3Path: nonexistentSqlite3)

        let result = await reader.readGrants(forClientIdentifier: nil)

        XCTAssertEqual(result, .unavailable(reason: .queryToolUnavailable))
    }
}

/// Simulates the modern-schema query failing (bad column) and the
/// legacy-schema query succeeding, distinguished by which column name
/// appears in the generated SQL.
actor LegacyFallbackRunner: ExternalCommandRunning {
    nonisolated func run(
        executable: String,
        arguments: [String],
        currentDirectory: String?,
        timeout: TimeInterval
    ) async -> ExternalCommandResult? {
        guard executable == "/usr/bin/sqlite3" else { return nil }
        let sql = arguments.last ?? ""
        if sql.contains("auth_value") {
            return ExternalCommandResult(standardOutput: "", standardError: "no such column: auth_value", exitCode: 1)
        }
        if sql.contains("allowed") {
            let sample = #"[{"client": "com.example.OldApp", "service": "kTCCServiceCamera", "allowed": 1, "last_modified": 1600000000}]"#
            return ExternalCommandResult(standardOutput: sample, standardError: "", exitCode: 0)
        }
        return nil
    }
}
