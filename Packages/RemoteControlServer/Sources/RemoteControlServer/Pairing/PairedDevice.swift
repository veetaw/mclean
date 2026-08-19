import Foundation

/// A mobile device that has completed pairing.
///
/// The raw bearer token is never stored — only its SHA-256 hash
/// (`tokenHash`, see `TokenGenerator`) — so that reading the persisted
/// store (today: in-memory, see `PairingStore`) never discloses a usable
/// credential.
public struct PairedDevice: Sendable, Codable, Identifiable, Equatable {
    public let id: UUID
    public var displayName: String
    public var tokenHash: String
    public let pairedAt: Date
    public var revokedAt: Date?

    public var isActive: Bool { revokedAt == nil }

    public init(
        id: UUID = UUID(),
        displayName: String,
        tokenHash: String,
        pairedAt: Date = Date(),
        revokedAt: Date? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.tokenHash = tokenHash
        self.pairedAt = pairedAt
        self.revokedAt = revokedAt
    }
}
