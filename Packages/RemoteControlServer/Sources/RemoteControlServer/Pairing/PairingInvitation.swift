import Foundation

/// A one-time, short-lived invitation the desktop app shows as a QR code
/// (or plain text, for the "type it in" fallback) to pair a new device.
///
/// Deliberately distinct from the long-lived `PairedDevice` token issued
/// once this invitation is redeemed via `POST /api/v1/pair`: a photographed
/// or shoulder-surfed QR code only ever exposes a credential that is
/// already single-use and expires within minutes
/// (`RemoteControlSettings.pairingInvitationLifetime`), never the device's
/// ongoing session token.
///
/// Rendering this as an actual QR code image is a `MainAppUI` concern —
/// this type only produces the data (token + ready-made pairing URL) that a
/// QR generator or a plain "enter this code" label would need.
public struct PairingInvitation: Sendable, Equatable {
    public let token: String
    public let expiresAt: Date

    public init(token: String, expiresAt: Date) {
        self.token = token
        self.expiresAt = expiresAt
    }

    /// Convenience for the desktop app: a full URL a QR code can encode,
    /// given the LAN-facing host (and the port `RemoteControlServer.start`
    /// returned). This package deliberately does not guess its own LAN IP —
    /// picking the right interface among possibly several (Wi-Fi, Ethernet,
    /// ...) is a host-app/OS concern. See `RemoteWebApp/README.md` for how
    /// the mobile web app consumes this URL.
    public func pairingURL(host: String, port: Int, scheme: String = "http") -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = port
        components.path = "/pair"
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        return components.url
    }
}

/// Internal record kept by `PairingStore` for a not-yet-redeemed invitation.
/// Only the hash of the token is persisted, matching `PairedDevice
/// .tokenHash`.
public struct PairingInvitationRecord: Sendable, Codable, Equatable {
    public let tokenHash: String
    public let createdAt: Date
    public let expiresAt: Date

    public init(tokenHash: String, createdAt: Date, expiresAt: Date) {
        self.tokenHash = tokenHash
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }
}
