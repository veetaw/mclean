import Foundation
import Network

/// Advertises this Mac's presence on the LAN via Bonjour/mDNS
/// (`_mcleanpro._tcp`) so an mDNS-aware client can find it without a
/// manually-entered IP address.
///
/// Implementation note: this `NWListener` is used *only* to publish the
/// service record — it never accepts or serves any application traffic.
/// The actual HTTP server is Swifter's own raw-BSD-socket listener (see
/// `RemoteControlServer`), bound to its own port. Two independent socket
/// stacks (Network.framework vs. a raw BSD socket) can't safely share one
/// TCP port in-process, so rather than fight that, this listener binds an
/// unrelated ephemeral port (`.any`) purely for mDNS registration and
/// publishes the *real* HTTP port inside the Bonjour TXT record
/// (`httpPort`); any connection that lands on this listener's own port
/// anyway is immediately dropped.
///
/// Practical caveat: today's `RemoteWebApp` is a plain browser page, and
/// browsers have no mDNS/Bonjour resolution API at all — so in practice
/// discovery happens via the QR-code pairing URL
/// (`RemoteControlServer.beginPairing`), which already encodes host, port,
/// and the pairing token directly. This advertiser satisfies PROMPT
/// MASTER §5.6's Bonjour requirement and is what a future native companion
/// client (which *can* resolve mDNS) would use instead of a typed-in IP.
public final class BonjourAdvertiser: @unchecked Sendable {
    public static let serviceType = "_mcleanpro._tcp"

    private let lock = NSLock()
    private var listener: NWListener?

    public init() {}

    public func start(advertisedHTTPPort: Int, deviceName: String, apiVersion: Int) throws {
        lock.lock()
        defer { lock.unlock() }
        stopLocked()

        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = false

        let newListener = try NWListener(using: parameters)
        newListener.service = NWListener.Service(
            name: deviceName,
            type: Self.serviceType,
            txtRecord: Self.txtRecord(httpPort: advertisedHTTPPort, apiVersion: apiVersion)
        )
        // Never actually serve anything on this listener's own port.
        newListener.newConnectionHandler = { connection in
            connection.cancel()
        }
        newListener.stateUpdateHandler = { _ in }
        newListener.start(queue: .global(qos: .utility))
        listener = newListener
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        stopLocked()
    }

    private func stopLocked() {
        listener?.cancel()
        listener = nil
    }

    static func txtRecord(httpPort: Int, apiVersion: Int) -> NWTXTRecord {
        NWTXTRecord([
            "httpPort": String(httpPort),
            "apiVersion": String(apiVersion)
        ])
    }
}
