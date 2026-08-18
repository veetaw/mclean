import CoreScanEngine
import Foundation

/// Interface for the reversible-quarantine subsystem (PROMPT MASTER §2:
/// "Quarantena reversibile di default").
///
/// ⚠️ CHECKPOINT: this file defines the *protocol* only. Per PROMPT MASTER §10
/// checkpoint 2, no concrete implementation that moves or deletes real user
/// data may be written until the user has explicitly confirmed. Do not
/// implement `QuarantineManaging` against real paths without that
/// confirmation — a test-fixture-only implementation (operating solely
/// inside a temp directory created by the test itself) is fine for exercising
/// this protocol's shape.
public protocol QuarantineManaging: Sendable {
    /// Moves `item` into the internal quarantine area. Never deletes
    /// anything directly. Returns a receipt that can be used to `restore` or
    /// that will be purged automatically once `retention` elapses.
    func quarantine(_ item: ScanItem, retention: QuarantinePolicy) async throws -> QuarantineReceipt

    /// Moves a previously-quarantined item back to its original location.
    /// Must succeed as long as the retention window hasn't elapsed and
    /// nothing has since been created at the original path.
    func restore(_ receipt: QuarantineReceipt) async throws

    /// Permanently deletes everything whose retention window has elapsed.
    /// This is the only method that performs an irreversible action, and it
    /// must never run implicitly — only from an explicit user action or a
    /// scheduled job the user has knowingly enabled.
    func purgeExpired() async throws -> [QuarantineReceipt]

    /// Lists everything currently sitting in quarantine, for the UI.
    func listActive() async throws -> [QuarantineReceipt]
}

/// How long a quarantined item is kept before it becomes eligible for
/// `purgeExpired`. Default matches PROMPT MASTER §2 (7 days), user-configurable.
public struct QuarantinePolicy: Sendable, Hashable, Codable {
    public var retentionDays: Int

    public static let `default` = QuarantinePolicy(retentionDays: 7)

    public init(retentionDays: Int) {
        self.retentionDays = retentionDays
    }
}

/// Record of a single quarantined item, enough to restore it or to explain
/// to the user what's sitting in quarantine and when it will be purged.
public struct QuarantineReceipt: Sendable, Identifiable, Hashable, Codable {
    public let id: UUID
    public let originalPath: String
    public let quarantinePath: String
    public let quarantinedAt: Date
    public let policy: QuarantinePolicy
    public let sourceItem: ScanItem

    public var purgeEligibleAt: Date {
        Calendar.current.date(byAdding: .day, value: policy.retentionDays, to: quarantinedAt) ?? quarantinedAt
    }

    public init(
        id: UUID = UUID(),
        originalPath: String,
        quarantinePath: String,
        quarantinedAt: Date,
        policy: QuarantinePolicy,
        sourceItem: ScanItem
    ) {
        self.id = id
        self.originalPath = originalPath
        self.quarantinePath = quarantinePath
        self.quarantinedAt = quarantinedAt
        self.policy = policy
        self.sourceItem = sourceItem
    }
}
