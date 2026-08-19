import Foundation

/// Best-effort `TCCPermissionReading` backed by shelling out to the
/// read-only `sqlite3` CLI (`sqlite3 -readonly -json <db> "SELECT ..."`)
/// against the on-disk `TCC.db`.
///
/// Shelling out to `sqlite3 -readonly` rather than linking SQLite directly
/// keeps this read auditable as "just another read-only subprocess call",
/// matching the pattern (and the hard constraint) every other subprocess
/// call in this package follows, and avoids adding a C-interop dependency
/// for what is fundamentally a handful of best-effort `SELECT`s.
///
/// Tries the modern (`auth_value`) column first — the schema for every
/// currently-supported macOS release — and falls back to the legacy
/// (`allowed`) column only if that fails, as a documented best-effort for
/// an old `TCC.db` encountered via, e.g., a migrated user account. If both
/// fail, distinguishes "sqlite3 isn't installed" from "the query itself
/// failed" (almost always: no Full Disk Access) so callers can show the
/// right guidance instead of a generic error.
public struct TCCDatabaseReader: TCCPermissionReading {
    private let commandRunner: ExternalCommandRunning
    private let sqlite3Path: String
    private let databasePath: String
    private let timeout: TimeInterval

    /// - Parameter databasePath: Defaults to the **user** TCC database,
    ///   `~/Library/Application Support/com.apple.TCC/TCC.db`. The
    ///   system-wide database (`/Library/Application Support/com.apple.TCC/TCC.db`,
    ///   covering machine-level grants) additionally requires root and is
    ///   not targeted by this default — pass its path explicitly if a
    ///   privileged caller needs it; this type applies no special handling
    ///   either way, since a plain permission failure degrades the same way
    ///   for both paths (`.fullDiskAccessRequired`).
    public init(
        databasePath: String = NSHomeDirectory() + "/Library/Application Support/com.apple.TCC/TCC.db",
        sqlite3Path: String = "/usr/bin/sqlite3",
        timeout: TimeInterval = 5
    ) {
        self.databasePath = databasePath
        self.commandRunner = RealExternalCommandRunner()
        self.sqlite3Path = sqlite3Path
        self.timeout = timeout
    }

    init(
        databasePath: String,
        commandRunner: ExternalCommandRunning,
        sqlite3Path: String = "/usr/bin/sqlite3",
        timeout: TimeInterval = 5
    ) {
        self.databasePath = databasePath
        self.commandRunner = commandRunner
        self.sqlite3Path = sqlite3Path
        self.timeout = timeout
    }

    public func readGrants(forClientIdentifier clientIdentifier: String?) async -> TCCReadResult {
        guard FileManager.default.fileExists(atPath: databasePath) else {
            return .unavailable(reason: .databaseNotFound)
        }

        if let rows = await queryAccessTable(schema: .modern, clientIdentifier: clientIdentifier) {
            return .grants(rows)
        }
        if let rows = await queryAccessTable(schema: .legacy, clientIdentifier: clientIdentifier) {
            return .grants(rows)
        }

        guard FileManager.default.isExecutableFile(atPath: sqlite3Path) else {
            return .unavailable(reason: .queryToolUnavailable)
        }
        return .unavailable(reason: .fullDiskAccessRequired)
    }

    /// Runs one schema's `SELECT`. Returns `nil` (never `[]` for "the
    /// column doesn't exist") on any failure, so `readGrants` can tell
    /// "this schema doesn't apply, try the other one" apart from "this
    /// schema applies and genuinely has zero rows".
    private func queryAccessTable(schema: TCCSchemaHint, clientIdentifier: String?) async -> [TCCGrant]? {
        let valueColumn = schema == .modern ? "auth_value" : "allowed"
        var sql = "SELECT client, service, \(valueColumn), last_modified FROM access"
        if let clientIdentifier {
            let escaped = clientIdentifier.replacingOccurrences(of: "'", with: "''")
            sql += " WHERE client = '\(escaped)'"
        }
        sql += ";"

        guard let result = await commandRunner.run(
            executable: sqlite3Path,
            arguments: ["-readonly", "-json", databasePath, sql],
            currentDirectory: nil,
            timeout: timeout
        ), result.exitCode == 0 else { return nil }

        let trimmed = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard let data = trimmed.data(using: .utf8) else { return nil }

        struct Row: Decodable {
            let client: String
            let service: String
            let auth_value: Int?
            let allowed: Int?
            let last_modified: Double?
        }
        guard let rows = try? JSONDecoder().decode([Row].self, from: data) else { return nil }

        return rows.map { row in
            let rawValue = schema == .modern ? row.auth_value : row.allowed
            return TCCGrant(
                clientIdentifier: row.client,
                service: TCCServiceIdentifier(rawValue: row.service),
                authorizationValue: TCCAuthorizationValue(rawValue: rawValue, schema: schema),
                lastModified: row.last_modified.map(Date.init(timeIntervalSince1970:))
            )
        }
    }
}
