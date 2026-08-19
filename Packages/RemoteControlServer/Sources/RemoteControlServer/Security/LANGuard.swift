import Foundation

/// Decides whether a peer IP address sits inside the local network segment:
/// private IPv4 ranges, IPv4 link-local, IPv4 loopback, or their IPv6
/// equivalents.
///
/// This is the actual LAN-only enforcement boundary for
/// `RemoteControlServer` — see that file's module-level documentation for
/// why the server still binds broadly (0.0.0.0, so it's reachable from
/// whichever interface — Wi-Fi, Ethernet, ... — the OS handed a LAN IP)
/// while every *accepted connection* is checked against this, using the
/// transport-layer peer address Swifter reports (`getpeername`), never a
/// client-supplied `Host`/`Origin`/`X-Forwarded-For` header (all trivially
/// spoofable and explicitly not trusted for anything security-relevant).
public enum LANGuard {
    public static func isLANOrLocalAddress(_ rawAddress: String?) -> Bool {
        guard let rawAddress, !rawAddress.isEmpty else { return false }
        // Strip an IPv6 zone id, e.g. "fe80::1%en0" -> "fe80::1".
        let address = rawAddress.split(separator: "%", maxSplits: 1).first.map(String.init) ?? rawAddress

        if let octets = ipv4Octets(address) {
            return isPrivateIPv4(octets)
        }
        return isLocalIPv6(address)
    }

    private static func ipv4Octets(_ address: String) -> [UInt8]? {
        let parts = address.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var octets = [UInt8]()
        octets.reserveCapacity(4)
        for part in parts {
            guard let value = UInt8(part) else { return nil }
            octets.append(value)
        }
        return octets
    }

    private static func isPrivateIPv4(_ octets: [UInt8]) -> Bool {
        switch octets[0] {
        case 127: return true // 127.0.0.0/8 loopback
        case 10: return true // 10.0.0.0/8
        case 172: return (16...31).contains(octets[1]) // 172.16.0.0/12
        case 192: return octets[1] == 168 // 192.168.0.0/16
        case 169: return octets[1] == 254 // 169.254.0.0/16 link-local
        default: return false
        }
    }

    private static func isLocalIPv6(_ address: String) -> Bool {
        let lowered = address.lowercased()
        if lowered == "::1" { return true } // loopback

        // IPv4-mapped, e.g. "::ffff:192.168.1.5".
        if lowered.hasPrefix("::ffff:"),
           let mapped = lowered.split(separator: ":").last,
           let octets = ipv4Octets(String(mapped)) {
            return isPrivateIPv4(octets)
        }

        // Inspect the first 16-bit group's high byte/bits rather than doing
        // a naive string-prefix check, since IPv6 groups omit leading
        // zeros: "fca::1" is NOT in fc00::/7 (its first group is 0x0fca,
        // high byte 0x0f), even though the string starts with "fc".
        guard let firstGroup = lowered.split(separator: ":", omittingEmptySubsequences: false).first,
              !firstGroup.isEmpty, firstGroup.count <= 4,
              let value = UInt16(firstGroup, radix: 16) else {
            return false
        }
        let highByte = UInt8(value >> 8)
        if highByte == 0xfc || highByte == 0xfd { return true } // fc00::/7 unique-local
        if highByte == 0xfe {
            let lowByteTopTwoBits = value & 0x00c0
            return lowByteTopTwoBits == 0x0080 // fe80::/10 link-local
        }
        return false
    }
}
