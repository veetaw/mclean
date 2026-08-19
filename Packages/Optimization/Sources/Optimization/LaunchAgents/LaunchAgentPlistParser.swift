import Foundation

/// Read-only parser/discoverer for `launchd.plist`-format files, backed by
/// `Foundation.PropertyListSerialization` — a standard, documented API, not
/// a private one. Every entry point here is designed to degrade to "nothing
/// found" rather than throw: a single missing directory, unreadable file,
/// or corrupt plist must never abort a caller's whole scan.
enum LaunchAgentPlistParser {
    /// Non-recursive listing of `*.plist` files directly inside
    /// `directory`, sorted for deterministic output. Returns `[]` for a
    /// directory that doesn't exist or isn't readable.
    static func discoverPlistPaths(in directory: String, fileManager: FileManager = .default) -> [String] {
        guard let entries = try? fileManager.contentsOfDirectory(atPath: directory) else { return [] }
        return entries
            .filter { $0.hasSuffix(".plist") }
            .sorted()
            .map { directory + "/" + $0 }
    }

    /// Parses one plist file into a `LaunchAgentPlist`.
    ///
    /// Returns `nil` — never throws — for anything that isn't a valid,
    /// dictionary-rooted property list: a missing/unreadable file, corrupt
    /// XML/binary plist data, or a plist whose root value isn't a
    /// dictionary. Callers should skip `nil` results and continue scanning
    /// the rest of the directory.
    static func parse(
        contentsOfFile path: String,
        scope: LaunchAgentPlist.Scope,
        fileManager: FileManager = .default
    ) -> LaunchAgentPlist? {
        guard let data = fileManager.contents(atPath: path), !data.isEmpty else { return nil }
        guard let raw = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) else {
            return nil
        }
        guard let dict = raw as? [String: Any] else { return nil }

        let label = dict["Label"] as? String

        var program = dict["Program"] as? String
        if program == nil,
           let args = dict["ProgramArguments"] as? [Any],
           let first = args.first as? String {
            program = first
        }

        return LaunchAgentPlist(
            path: path,
            label: label,
            program: program,
            runAtLoad: boolValue(dict["RunAtLoad"]),
            keepAlive: keepAliveValue(dict["KeepAlive"]),
            scope: scope
        )
    }

    /// Convenience: discovers and parses every plist directly under
    /// `directory`, silently skipping any that fail to parse (see `parse`).
    static func discoverAndParse(
        in directory: String,
        scope: LaunchAgentPlist.Scope,
        fileManager: FileManager = .default
    ) -> [LaunchAgentPlist] {
        discoverPlistPaths(in: directory, fileManager: fileManager).compactMap {
            parse(contentsOfFile: $0, scope: scope, fileManager: fileManager)
        }
    }

    /// Plist booleans normally bridge straight to `Bool`; the `NSNumber`
    /// fallback is defensive for plist variants that decode them as a
    /// boxed number instead.
    private static func boolValue(_ value: Any?) -> Bool {
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.boolValue }
        return false
    }

    /// `KeepAlive` may be a bare boolean or a dictionary of finer-grained
    /// conditions (e.g. `{"SuccessfulExit": false}`); either present form
    /// is treated as "keep-alive behavior is configured."
    private static func keepAliveValue(_ value: Any?) -> Bool {
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.boolValue }
        if value is [String: Any] { return true }
        return false
    }
}
