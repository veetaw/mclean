import Foundation

/// Runtime-tunable behavior for `RemoteControlServer`. A single value type so
/// the desktop app can persist/restore it however it likes (e.g. alongside
/// its own `@AppStorage`/settings store) and hand it to `RemoteControlServer`
/// at init, or push updates via `RemoteControlServer.updateSettings(_:)`.
public struct RemoteControlSettings: Sendable, Codable, Equatable {
    /// When `true`, a paired mobile device is allowed to call the HTTP
    /// `POST /api/v1/approval-requests/{id}/fulfill` endpoint with
    /// `"decision": "approve"` and have the quarantine happen immediately —
    /// still exclusively through the injected `QuarantineManaging`
    /// implementation, still fully logged/receipted, but without a human
    /// confirming on the Mac itself first.
    ///
    /// Defaults to `false` (mobile devices may only *request* approval; a
    /// human on the Mac must fulfill it via `RemoteControlServer
    /// .fulfillApprovalRequest`, called in-process, never over HTTP).
    ///
    /// ⚠️ Not wired to any UI yet. `MainAppUI` (not yet scaffolded) owns
    /// deciding whether/how to expose this as a user-facing settings toggle.
    /// This package only defines the flag and honors it.
    public var allowMobileApprovalFulfillment: Bool

    /// Best-effort cap on accepted request bodies, in bytes. See
    /// `HTTP/TransportGuards.swift` for why this is enforced *after*
    /// Swifter has already read the body off the socket rather than
    /// preventing the read itself — Swifter's parser doesn't expose a hook
    /// to abort mid-read based on `Content-Length`.
    public var maxRequestBodyBytes: Int

    /// Requests allowed per remote address within `rateLimitWindowSeconds`.
    /// Changing this after `RemoteControlServer.init` has no effect until
    /// the server is re-created — the limiter is sized once at init.
    public var rateLimitRequestsPerWindow: Int
    public var rateLimitWindowSeconds: TimeInterval

    /// How long a pairing invitation (the token embedded in the desktop
    /// app's QR code) stays redeemable before `beginPairing()` must be
    /// called again. Read live on every `beginPairing()` call.
    public var pairingInvitationLifetime: TimeInterval

    public init(
        allowMobileApprovalFulfillment: Bool = false,
        maxRequestBodyBytes: Int = 64 * 1024,
        rateLimitRequestsPerWindow: Int = 120,
        rateLimitWindowSeconds: TimeInterval = 60,
        pairingInvitationLifetime: TimeInterval = 300
    ) {
        self.allowMobileApprovalFulfillment = allowMobileApprovalFulfillment
        self.maxRequestBodyBytes = maxRequestBodyBytes
        self.rateLimitRequestsPerWindow = rateLimitRequestsPerWindow
        self.rateLimitWindowSeconds = rateLimitWindowSeconds
        self.pairingInvitationLifetime = pairingInvitationLifetime
    }
}
