import CoreScanEngine
import Foundation

/// Errors specific to the concrete, real-filesystem quarantine implementation.
public enum QuarantineError: Error, Sendable, Equatable, CustomStringConvertible {
    /// Defense in depth: even though callers are expected to have already
    /// classified the item via `SafetyClassifying`, the quarantine manager
    /// independently re-checks the hardcoded denylist before ever touching
    /// disk, and refuses if it matches — a caller bug must never be able to
    /// move a protected path.
    case pathForbidden(String)
    case sourceNotFound(String)
    case receiptNotFound(UUID)
    /// Restoring would overwrite something that already exists at the
    /// original location — refuse rather than silently clobber it.
    case restoreDestinationOccupied(String)
    case retentionNotElapsed(UUID)
    case underlying(String)

    public var description: String {
        switch self {
        case .pathForbidden(let path): "Path is forbidden and cannot be quarantined: \(path)"
        case .sourceNotFound(let path): "Source path does not exist: \(path)"
        case .receiptNotFound(let id): "No quarantine receipt with id \(id)"
        case .restoreDestinationOccupied(let path): "Cannot restore: something already exists at \(path)"
        case .retentionNotElapsed(let id): "Retention window has not elapsed for receipt \(id)"
        case .underlying(let description): description
        }
    }
}

/// Real, on-disk implementation of `QuarantineManaging`.
///
/// Design:
/// - Quarantined items are **moved** (never copied+deleted-in-place, and
///   never touched by any multi-pass shredder) into a dedicated root, each
///   under its own UUID-named subdirectory to avoid filename collisions.
/// - A flat JSON manifest file tracks active receipts. This is intentionally
///   simple for Phase 1; PROMPT MASTER §3 calls for a SQLite-backed store
///   (GRDB or similar) for scan history/quarantine state longer-term — this
///   type's persistence can be swapped for that without changing its public
///   interface, since `QuarantineManaging` doesn't expose storage details.
/// - `purgeExpired()` is the only method that permanently deletes anything,
///   and only for receipts whose retention window has already elapsed. It
///   must only ever be invoked by an explicit user action or a scheduled job
///   the user has knowingly enabled — this type does not schedule itself.
public actor FileSystemQuarantineManager: QuarantineManaging {
    private let quarantineRootURL: URL
    private let manifestURL: URL
    private let fileManager: FileManager

    /// - Parameter quarantineRootURL: where quarantined files live. Defaults
    ///   to `~/Library/Application Support/MCleanPro/Quarantine`. Tests
    ///   should inject a temp directory instead of using the default.
    public init(
        quarantineRootURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        let root = quarantineRootURL ?? Self.defaultQuarantineRoot(fileManager: fileManager)
        self.quarantineRootURL = root
        self.manifestURL = root.appendingPathComponent("quarantine-manifest.json")
        self.fileManager = fileManager
    }

    public static func defaultQuarantineRoot(fileManager: FileManager = .default) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return appSupport.appendingPathComponent("MCleanPro", isDirectory: true)
            .appendingPathComponent("Quarantine", isDirectory: true)
    }

    // MARK: - QuarantineManaging

    public func quarantine(_ item: ScanItem, retention: QuarantinePolicy) async throws -> QuarantineReceipt {
        try checkNotForbidden(item.path)

        guard fileManager.fileExists(atPath: item.path) else {
            throw QuarantineError.sourceNotFound(item.path)
        }

        try ensureDirectoryExists(quarantineRootURL)

        let receiptID = UUID()
        let itemFolder = quarantineRootURL.appendingPathComponent(receiptID.uuidString, isDirectory: true)
        try ensureDirectoryExists(itemFolder)

        let sourceURL = URL(fileURLWithPath: item.path)
        let destinationURL = itemFolder.appendingPathComponent(sourceURL.lastPathComponent)

        do {
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
        } catch {
            throw QuarantineError.underlying("Move failed: \(error.localizedDescription)")
        }

        let receipt = QuarantineReceipt(
            id: receiptID,
            originalPath: item.path,
            quarantinePath: destinationURL.path,
            quarantinedAt: Date(),
            policy: retention,
            sourceItem: item
        )

        var manifest = try loadManifest()
        manifest.append(receipt)
        try saveManifest(manifest)

        return receipt
    }

    public func restore(_ receipt: QuarantineReceipt) async throws {
        var manifest = try loadManifest()
        guard let index = manifest.firstIndex(where: { $0.id == receipt.id }) else {
            throw QuarantineError.receiptNotFound(receipt.id)
        }

        let quarantineURL = URL(fileURLWithPath: receipt.quarantinePath)
        let originalURL = URL(fileURLWithPath: receipt.originalPath)

        guard !fileManager.fileExists(atPath: originalURL.path) else {
            throw QuarantineError.restoreDestinationOccupied(receipt.originalPath)
        }

        try ensureDirectoryExists(originalURL.deletingLastPathComponent())

        do {
            try fileManager.moveItem(at: quarantineURL, to: originalURL)
        } catch {
            throw QuarantineError.underlying("Restore move failed: \(error.localizedDescription)")
        }

        // Best-effort cleanup of the now-empty per-item quarantine folder.
        try? fileManager.removeItem(at: quarantineURL.deletingLastPathComponent())

        manifest.remove(at: index)
        try saveManifest(manifest)
    }

    public func purgeExpired() async throws -> [QuarantineReceipt] {
        var manifest = try loadManifest()
        let now = Date()
        let expired = manifest.filter { $0.purgeEligibleAt <= now }

        for receipt in expired {
            let quarantineURL = URL(fileURLWithPath: receipt.quarantinePath)
            // Permanent deletion — the only irreversible step in this type.
            try? fileManager.removeItem(at: quarantineURL.deletingLastPathComponent())
        }

        manifest.removeAll { receipt in expired.contains(where: { $0.id == receipt.id }) }
        try saveManifest(manifest)

        return expired
    }

    public func listActive() async throws -> [QuarantineReceipt] {
        try loadManifest()
    }

    // MARK: - Internal helpers

    private func checkNotForbidden(_ path: String) throws {
        if let reason = Denylist.forbiddenReason(forPath: path) {
            throw QuarantineError.pathForbidden(reason)
        }
        if Denylist.isLikelyBootVolumeRoot(path) {
            throw QuarantineError.pathForbidden("Path is a volume root: \(path)")
        }
    }

    private func ensureDirectoryExists(_ url: URL) throws {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            return
        }
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func loadManifest() throws -> [QuarantineReceipt] {
        guard fileManager.fileExists(atPath: manifestURL.path) else { return [] }
        let data = try Data(contentsOf: manifestURL)
        if data.isEmpty { return [] }
        return try JSONDecoder.mcleanDefault.decode([QuarantineReceipt].self, from: data)
    }

    private func saveManifest(_ manifest: [QuarantineReceipt]) throws {
        try ensureDirectoryExists(quarantineRootURL)
        let data = try JSONEncoder.mcleanDefault.encode(manifest)
        try data.write(to: manifestURL, options: .atomic)
    }
}

extension JSONDecoder {
    fileprivate static var mcleanDefault: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

extension JSONEncoder {
    fileprivate static var mcleanDefault: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
