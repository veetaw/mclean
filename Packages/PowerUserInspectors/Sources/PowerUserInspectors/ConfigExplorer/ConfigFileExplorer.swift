import Foundation
#if canImport(PrivilegedHelperXPC)
import PrivilegedHelperXPC
#endif

/// A read-only-by-default browser over `/etc`, `~/.config`, and
/// home-directory dotfiles: list entries with metadata, read file contents,
/// and — as the one explicit, opt-in mutating operation —
/// `write(newContents:to:)`, which **always** takes a timestamped backup of
/// the existing content before overwriting it. There is no lower-level
/// "just write, no backup" method anywhere in this type; every code path
/// that ends in `FileManager` writing to `path` goes through `backup(path:)`
/// first.
///
/// **On `/etc` writes**: most `/etc` files are root-owned. This type makes
/// no attempt to escalate privileges — a write this process's user can't
/// perform will simply surface the underlying `NSFileWriteNoPermissionError`
/// via `ConfigFileExplorerError.writeFailed`, same as any other unprivileged
/// write attempt. `PrivilegedHelperXPC.PrivilegedHelperProtocol` doesn't
/// currently expose a generic "write file" capability (only
/// quarantine/restore/maintenance-task operations), so this package never
/// attempts to call through XPC for config writes today; see
/// `PrivilegedWriteSeam` for where that would plug in if the product ever
/// needs unprivileged-process `/etc` editing to work.
public struct ConfigFileExplorer: Sendable {
    public enum RootKind: Sendable, CaseIterable {
        case etc
        case userConfig
        case homeDotfiles
    }

    public let etcDirectory: URL
    public let homeDirectory: URL
    public let backupDirectory: URL

    /// - Parameter backupDirectory: Defaults to
    ///   `~/Library/Application Support/MCleanPro/ConfigBackups`. Tests pass
    ///   a temp directory so no test ever writes outside its own sandbox.
    public init(
        etcDirectory: URL = URL(fileURLWithPath: "/etc"),
        homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory()),
        backupDirectory: URL? = nil
    ) {
        self.etcDirectory = etcDirectory
        self.homeDirectory = homeDirectory
        self.backupDirectory = backupDirectory ?? homeDirectory
            .appendingPathComponent("Library/Application Support/MCleanPro/ConfigBackups", isDirectory: true)
    }

    // MARK: - Listing

    public func listEntries(in root: RootKind) -> [ConfigEntry] {
        switch root {
        case .etc:
            return listEntries(atDirectory: etcDirectory.path)
        case .userConfig:
            return listEntries(atDirectory: homeDirectory.appendingPathComponent(".config", isDirectory: true).path)
        case .homeDotfiles:
            return listEntries(atDirectory: homeDirectory.path).filter { $0.name.hasPrefix(".") }
        }
    }

    /// Non-recursive listing of `directoryPath`, for browsing into a
    /// subdirectory returned by `listEntries(in:)`. Returns `[]` for a path
    /// that doesn't exist or isn't readable, rather than throwing.
    public func listEntries(atDirectory directoryPath: String) -> [ConfigEntry] {
        PowerUserFS.directoryEntries(directoryPath).compactMap { name -> ConfigEntry? in
            let path = directoryPath + "/" + name
            guard PowerUserFS.exists(path) else { return nil }
            let isDirectory = PowerUserFS.isDirectory(path)
            return ConfigEntry(
                path: path,
                name: name,
                isDirectory: isDirectory,
                sizeBytes: isDirectory ? nil : PowerUserFS.fileSize(path),
                modificationDate: PowerUserFS.modificationDate(path),
                guessedSyntax: isDirectory ? .unknown : ConfigSyntaxGuesser.guess(forPath: path)
            )
        }
    }

    // MARK: - Reading

    public func readContents(at path: String) throws -> String {
        guard PowerUserFS.exists(path) else { throw ConfigFileExplorerError.fileNotFound(path) }
        guard !PowerUserFS.isDirectory(path) else { throw ConfigFileExplorerError.notARegularFile(path) }
        guard let data = FileManager.default.contents(atPath: path) else {
            throw ConfigFileExplorerError.fileNotFound(path)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw ConfigFileExplorerError.notUTF8Decodable(path)
        }
        return text
    }

    // MARK: - Diffing

    /// Line-based diff between `path`'s current contents (empty string if
    /// the file doesn't exist yet) and `newContents`, without writing
    /// anything — for a "review before saving" step ahead of
    /// `write(newContents:to:)`.
    public func previewDiff(newContents: String, to path: String) -> [LineDiff.Change] {
        let current = (try? readContents(at: path)) ?? ""
        return LineDiff.diff(oldContents: current, newContents: newContents)
    }

    // MARK: - Writing (always backed up first)

    /// Overwrites `path` with `newContents`. Always takes a timestamped
    /// backup of the pre-existing content first (skipped only when `path`
    /// doesn't exist yet — there's nothing to back up when creating a file
    /// for the first time). Restricted to paths under `etcDirectory` or
    /// `homeDirectory` — anything else throws `pathOutsideAllowedRoots`
    /// rather than silently writing wherever it's pointed.
    @discardableResult
    public func write(newContents: String, to path: String) throws -> ConfigBackupReceipt {
        guard isPathWithinAllowedRoots(path) else {
            throw ConfigFileExplorerError.pathOutsideAllowedRoots(path)
        }

        let receipt = try backup(path: path)
        do {
            try newContents.write(toFile: path, atomically: true, encoding: .utf8)
        } catch {
            throw ConfigFileExplorerError.writeFailed(path, underlying: String(describing: error))
        }
        return receipt
    }

    private func isPathWithinAllowedRoots(_ path: String) -> Bool {
        let canonicalPath = Self.canonicalPath(path)
        let allowedRoots = [Self.canonicalPath(etcDirectory.path), Self.canonicalPath(homeDirectory.path)]
        return allowedRoots.contains { root in canonicalPath == root || canonicalPath.hasPrefix(root + "/") }
    }

    /// Resolves `path` to its canonical (symlink-free) form the same way
    /// regardless of whether `path` itself exists yet.
    ///
    /// `URL.standardizedFileURL`/`NSString.standardizingPath` only collapse
    /// the well-known `/private/var`, `/private/tmp`, `/private/etc`
    /// symlinks when the *exact* path already exists on disk — for a
    /// not-yet-created file (e.g. a brand-new config being written for the
    /// first time) they leave the `/private/...` form untouched. Comparing
    /// that inconsistently-normalized path against an existing,
    /// already-collapsed root would make `write(newContents:to:)`
    /// incorrectly reject legitimate new files. Resolving via the nearest
    /// existing ancestor directory keeps normalization consistent either
    /// way.
    private static func canonicalPath(_ path: String) -> String {
        if let resolved = PowerUserFS.realpath(path) {
            return resolved
        }
        let url = URL(fileURLWithPath: path)
        let parent = url.deletingLastPathComponent().path
        let resolvedParent = PowerUserFS.realpath(parent) ?? parent
        return resolvedParent + "/" + url.lastPathComponent
    }

    private func backup(path: String) throws -> ConfigBackupReceipt {
        guard PowerUserFS.exists(path) else {
            return ConfigBackupReceipt(originalPath: path, backupPath: nil, createdAt: Date())
        }

        let timestamp = Self.backupTimestampFormatter.string(from: Date())
        let sanitizedOriginal = path.replacingOccurrences(of: "/", with: "_")
        let uniqueSuffix = UUID().uuidString.prefix(8)
        let backupFileName = "\(sanitizedOriginal).\(timestamp).\(uniqueSuffix).bak"
        let backupPath = backupDirectory.appendingPathComponent(backupFileName)

        do {
            try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: backupPath.path) {
                try FileManager.default.removeItem(at: backupPath)
            }
            try FileManager.default.copyItem(atPath: path, toPath: backupPath.path)
        } catch {
            throw ConfigFileExplorerError.backupFailed(path, underlying: String(describing: error))
        }

        return ConfigBackupReceipt(originalPath: path, backupPath: backupPath.path, createdAt: Date())
    }

    private static let backupTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()
}

/// Record of a backup taken by `ConfigFileExplorer.write(newContents:to:)`.
/// `backupPath` is `nil` only when there was no pre-existing file to back
/// up (the write created a brand-new file).
public struct ConfigBackupReceipt: Sendable, Hashable, Codable {
    public let originalPath: String
    public let backupPath: String?
    public let createdAt: Date

    public init(originalPath: String, backupPath: String?, createdAt: Date) {
        self.originalPath = originalPath
        self.backupPath = backupPath
        self.createdAt = createdAt
    }
}

public enum ConfigFileExplorerError: Error, Sendable, Equatable {
    case fileNotFound(String)
    case notARegularFile(String)
    case notUTF8Decodable(String)
    case pathOutsideAllowedRoots(String)
    case backupFailed(String, underlying: String)
    case writeFailed(String, underlying: String)
}

/// Marks the seam where a future privileged "write config file" XPC call
/// would plug in for root-owned `/etc` paths this process's own user can't
/// write. Not implemented — `PrivilegedHelperProtocol` currently exposes no
/// generic file-write capability, so no call is ever made through it.
/// Referencing the protocol's constants here (rather than only in a doc
/// comment) keeps this seam checked by the compiler: if
/// `PrivilegedHelperProtocol` grows a write capability, a call site can be
/// wired in here without the import being missed.
enum PrivilegedWriteSeam {
    #if canImport(PrivilegedHelperXPC)
    /// The XPC Mach service name a future privileged write would target.
    static let helperMachServiceName = PrivilegedHelperConstants.machServiceName
    #endif
}
