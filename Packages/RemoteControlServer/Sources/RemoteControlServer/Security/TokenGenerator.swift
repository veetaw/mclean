import CryptoKit
import Foundation

/// Cryptographically-random token generation and one-way hashing, used for
/// both pairing invitations and per-device bearer tokens.
public enum TokenGenerator {
    /// Generates a URL-safe, base64url-encoded random token.
    /// - Parameter byteCount: raw entropy before encoding. 32 bytes (256
    ///   bits) by default — comfortably beyond what's brute-forceable
    ///   against a LAN-only, rate-limited HTTP API.
    public static func generateToken(byteCount: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        var rng = SystemRandomNumberGenerator()
        for index in bytes.indices {
            bytes[index] = UInt8.random(in: 0...255, using: &rng)
        }
        return Data(bytes).base64URLEncodedString()
    }

    /// SHA-256 hash of a token, hex-encoded. Tokens are only ever persisted
    /// hashed (see `PairedDevice.tokenHash`, `PairingInvitationRecord
    /// .tokenHash`) — never in plaintext — so that reading the store never
    /// discloses a usable credential.
    public static func hash(_ token: String) -> String {
        let digest = SHA256.hash(data: Data(token.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
