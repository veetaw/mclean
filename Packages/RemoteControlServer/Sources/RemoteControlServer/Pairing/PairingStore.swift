import Foundation

/// Persistence boundary for paired-device tokens and outstanding pairing
/// invitations.
///
/// PROMPT MASTER §3 calls for scan history/app state to live in a SQLite
/// (GRDB-backed) store; wiring `PairingStore` to that is out of scope for
/// this package. `InMemoryPairingStore` below is enough to exercise the
/// full pairing/auth flow end-to-end and is what `RemoteControlServer` uses
/// by default, but nothing persists across a process relaunch until a real
/// SQLite-backed conformer is written elsewhere and injected at
/// `RemoteControlServer.init`. Keeping this protocol narrow (just the
/// device/invitation records, no SQL or scan-history concerns) is what
/// makes that swap possible without touching `RemoteControlServer` itself.
public protocol PairingStore: Sendable {
    func saveDevice(_ device: PairedDevice) async
    func device(forTokenHash tokenHash: String) async -> PairedDevice?
    func device(forID id: UUID) async -> PairedDevice?
    func allDevices() async -> [PairedDevice]
    func revokeDevice(id: UUID) async

    func saveInvitation(_ invitation: PairingInvitationRecord) async
    /// Atomically looks up and consumes (removes) a still-valid invitation
    /// matching `tokenHash`, returning it — or `nil` if it doesn't exist,
    /// already expired, or was already redeemed. Callers must treat all of
    /// those as the same generic "invalid pairing token" outcome so as not
    /// to leak which case occurred to an unauthenticated caller.
    func consumeInvitation(tokenHash: String, now: Date) async -> PairingInvitationRecord?
}

/// In-memory `PairingStore`. State does not survive a process relaunch —
/// see the persistence note on the protocol above.
public actor InMemoryPairingStore: PairingStore {
    private var devicesByID: [UUID: PairedDevice] = [:]
    private var invitationsByTokenHash: [String: PairingInvitationRecord] = [:]

    public init() {}

    public func saveDevice(_ device: PairedDevice) {
        devicesByID[device.id] = device
    }

    public func device(forTokenHash tokenHash: String) -> PairedDevice? {
        devicesByID.values.first { $0.tokenHash == tokenHash && $0.isActive }
    }

    public func device(forID id: UUID) -> PairedDevice? {
        devicesByID[id]
    }

    public func allDevices() -> [PairedDevice] {
        devicesByID.values.sorted { $0.pairedAt < $1.pairedAt }
    }

    public func revokeDevice(id: UUID) {
        guard var device = devicesByID[id] else { return }
        device.revokedAt = Date()
        devicesByID[id] = device
    }

    public func saveInvitation(_ invitation: PairingInvitationRecord) {
        invitationsByTokenHash[invitation.tokenHash] = invitation
    }

    public func consumeInvitation(tokenHash: String, now: Date) -> PairingInvitationRecord? {
        // One-time use: remove unconditionally so it can never be replayed,
        // whether or not it turns out to still be valid.
        guard let invitation = invitationsByTokenHash.removeValue(forKey: tokenHash) else {
            return nil
        }
        guard invitation.expiresAt > now else { return nil }
        return invitation
    }
}
