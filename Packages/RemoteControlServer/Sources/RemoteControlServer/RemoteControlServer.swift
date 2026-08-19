import CoreScanEngine
import Foundation
import SafetyRules
import Swifter

/// Embeds a small, LAN-only HTTP API (backed by Swifter — see
/// `ARCHITECTURE.md` checkpoint 1) plus Bonjour advertisement, so a paired
/// mobile browser on the same network can view scan findings and request
/// quarantine approvals without any manual IP entry.
///
/// ## LAN-only: how it's enforced
///
/// `start(port:bindAddress:)` binds Swifter's listener to `0.0.0.0`
/// (`bindAddress: nil`, the default) or to a caller-narrowed IPv4 address —
/// binding broadly is unavoidable in practice because the Mac's LAN IP is
/// DHCP-assigned per-interface (Wi-Fi vs. Ethernet) and this package has no
/// business guessing which one is "the" LAN interface. The actual
/// LAN-only boundary is enforced per-connection, independent of the bind
/// address: every request is checked by `LANGuard.isLANOrLocalAddress`
/// against the real transport-layer peer address Swifter reports via
/// `getpeername()` — never against a client-supplied `Host`, `Origin`, or
/// `X-Forwarded-For` header, all of which are trivially spoofable and are
/// never trusted for anything security-relevant here. A connection from
/// outside RFC1918 / link-local / loopback / IPv6 ULA ranges is rejected
/// with 403 before it ever reaches routing (see the `middleware` entry
/// registered in `registerRoutes()`).
///
/// This is the accepted MVP trade-off documented in `ARCHITECTURE.md`
/// ("HTTP vs. local TLS"): plain HTTP + per-device token auth, LAN-scoped
/// as above, with local TLS (e.g. mkcert-style) deferred.
///
/// ## What this package never does
///
/// It never performs a quarantine action on its own initiative. Every
/// destructive action funnels through the injected `QuarantineManaging`
/// conformer, gated by the same request/confirm semantics used everywhere
/// else in the app — see `ApprovalRequest` and `fulfillApprovalRequest`.
public final class RemoteControlServer: @unchecked Sendable {
    public static let apiVersion = 1
    public static let bonjourServiceType = BonjourAdvertiser.serviceType

    private let httpServer = HttpServer()
    private let bonjour = BonjourAdvertiser()
    private let scanSnapshotProvider: ScanSnapshotProviding
    private let quarantineManager: QuarantineManaging
    private let diskSpaceProvider: DiskSpaceProviding
    private let pairingStore: PairingStore
    private let approvalStore = ApprovalRequestStore()
    private let rateLimiter: RateLimiter
    private let staticFileRoot: URL?
    private let advertisedServiceName: String

    private let stateLock = NSLock()
    private var _settings: RemoteControlSettings
    private var _isRunning = false

    /// - Parameters:
    ///   - scanSnapshotProvider: Reflects the desktop app's own last scan
    ///     results + `SafetyRules` verdicts. This package never scans or
    ///     classifies on its own.
    ///   - quarantineManager: The *only* thing ever asked to move a file.
    ///     Always the same conformer (e.g. `FileSystemQuarantineManager`)
    ///     used by the rest of the app, so quarantine semantics never
    ///     diverge between the desktop UI and remote control.
    ///   - diskSpaceProvider: Defaults to the real boot volume; inject a
    ///     fake in tests.
    ///   - pairingStore: Defaults to an in-memory store. See `PairingStore`
    ///     for the persistence note (SQLite-backed storage is out of scope
    ///     for this package).
    ///   - settings: See `RemoteControlSettings`.
    ///   - staticFileRoot: If provided, `RemoteWebApp`'s static assets are
    ///     served from this directory at the server's root, same-origin
    ///     with the JSON API. If `nil`, only the JSON API is served (useful
    ///     if the host app wants to serve the web app some other way).
    ///   - advertisedServiceName: Shown as the Bonjour service instance
    ///     name. Unrelated to a paired device's own display name (that
    ///     comes from the mobile client at pairing time — see `handlePair`).
    public init(
        scanSnapshotProvider: ScanSnapshotProviding,
        quarantineManager: QuarantineManaging,
        diskSpaceProvider: DiskSpaceProviding = SystemDiskSpaceProvider(),
        pairingStore: PairingStore = InMemoryPairingStore(),
        settings: RemoteControlSettings = RemoteControlSettings(),
        staticFileRoot: URL? = nil,
        advertisedServiceName: String = "MClean Pro"
    ) {
        self.scanSnapshotProvider = scanSnapshotProvider
        self.quarantineManager = quarantineManager
        self.diskSpaceProvider = diskSpaceProvider
        self.pairingStore = pairingStore
        self._settings = settings
        self.rateLimiter = RateLimiter(
            maxRequests: settings.rateLimitRequestsPerWindow,
            window: settings.rateLimitWindowSeconds
        )
        self.staticFileRoot = staticFileRoot
        self.advertisedServiceName = advertisedServiceName
        registerRoutes()
    }

    // MARK: - Settings

    /// Current settings. Thread-safe; readable from HTTP handler closures
    /// (arbitrary background threads) and from the desktop app's own code.
    public var settings: RemoteControlSettings {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _settings
    }

    /// Updates settings in place. `allowMobileApprovalFulfillment`,
    /// `maxRequestBodyBytes`, and `pairingInvitationLifetime` are read live
    /// on every request/call; the rate-limit fields are sized once at
    /// `init` and only take effect on the next `RemoteControlServer`
    /// instance.
    public func updateSettings(_ newValue: RemoteControlSettings) {
        stateLock.lock()
        _settings = newValue
        stateLock.unlock()
    }

    // MARK: - Lifecycle

    public var isRunning: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _isRunning
    }

    /// Starts the HTTP server and Bonjour advertisement.
    /// - Parameters:
    ///   - port: TCP port to listen on. Pass `0` for tests/ephemeral use —
    ///     the actual bound port is returned.
    ///   - bindAddress: Narrows the bind interface to a specific IPv4
    ///     address instead of all interfaces (`0.0.0.0`). Optional
    ///     hardening for an operator who knows their LAN interface's IP;
    ///     `LANGuard`'s per-connection check (see the type-level docs
    ///     above) is the real LAN-only boundary either way.
    /// - Returns: The actual bound TCP port.
    @discardableResult
    public func start(port: UInt16 = 8080, bindAddress: String? = nil) throws -> UInt16 {
        guard !isRunning else { throw RemoteControlServerError.alreadyRunning }

        httpServer.listenAddressIPv4 = bindAddress
        try httpServer.start(port, forceIPv4: true)
        let boundPort = try httpServer.port()

        do {
            try bonjour.start(
                advertisedHTTPPort: boundPort,
                deviceName: advertisedServiceName,
                apiVersion: Self.apiVersion
            )
        } catch {
            // Bonjour advertising is a discovery convenience, not a
            // security boundary. If it fails (e.g. Local Network
            // permission not yet granted by the user), the HTTP server
            // still runs fine — QR-code pairing, which encodes host+port
            // directly, doesn't depend on it.
        }

        stateLock.lock()
        _isRunning = true
        stateLock.unlock()
        return UInt16(boundPort)
    }

    public func stop() {
        bonjour.stop()
        httpServer.stop()
        stateLock.lock()
        _isRunning = false
        stateLock.unlock()
    }

    public func boundPort() throws -> Int {
        guard isRunning else { throw RemoteControlServerError.notRunning }
        return try httpServer.port()
    }

    // MARK: - Desktop-facing API (in-process, no HTTP/auth involved)

    /// Generates a new one-time pairing invitation for the desktop app to
    /// show as a QR code (or plain text). See `PairingInvitation`.
    public func beginPairing() async -> PairingInvitation {
        let token = TokenGenerator.generateToken()
        let expiresAt = Date().addingTimeInterval(settings.pairingInvitationLifetime)
        await pairingStore.saveInvitation(
            PairingInvitationRecord(tokenHash: TokenGenerator.hash(token), createdAt: Date(), expiresAt: expiresAt)
        )
        return PairingInvitation(token: token, expiresAt: expiresAt)
    }

    public func pairedDevices() async -> [PairedDevice] {
        await pairingStore.allDevices()
    }

    /// Admin-initiated revocation (e.g. from a "paired devices" settings
    /// list on the Mac). Deliberately not exposed over HTTP — only a
    /// device's *own* token can be revoked via the HTTP API
    /// (`POST /api/v1/pair/revoke`), so a compromised device can't revoke
    /// another device's access remotely.
    public func revokeDevice(_ id: UUID) async {
        await pairingStore.revokeDevice(id: id)
    }

    public func currentApprovalRequests(status: ApprovalStatus? = nil) async -> [ApprovalRequest] {
        await approvalStore.all(status: status)
    }

    /// Desktop-initiated fulfillment — the normal path when a human
    /// approves/rejects a mobile-originated request from the Mac app's own
    /// UI. Always available regardless of
    /// `RemoteControlSettings.allowMobileApprovalFulfillment` (that flag
    /// only gates the *HTTP* fulfillment path for mobile-initiated
    /// approval — see `handleFulfillApprovalRequest`).
    ///
    /// Returns the updated request (whose `status` reflects the outcome —
    /// `.fulfilled`, `.rejected`, or `.failed` with `failureReason` set),
    /// or `nil` only if `id` doesn't match any known approval request.
    @discardableResult
    public func fulfillApprovalRequest(id: UUID, decision: ApprovalDecision) async -> ApprovalRequest? {
        switch await resolveApprovalRequest(id: id, decision: decision, actor: .desktop) {
        case .success(let approval):
            return approval
        case .failure(.notFound):
            return nil
        case .failure:
            return await approvalStore.get(id)
        }
    }

    // MARK: - Route registration

    private func registerRoutes() {
        httpServer.middleware.append { [weak self] request in
            self?.enforceTransportGuards(for: request)
        }

        httpServer.GET["/api/v1/health"] = route { server, _ in server.handleHealth() }
        httpServer.POST["/api/v1/pair"] = route { server, request in server.handlePair(request) }
        httpServer.POST["/api/v1/pair/revoke"] = route { server, request in
            server.withAuthenticatedDevice(request) { device in server.handleSelfRevoke(device: device) }
        }
        httpServer.GET["/api/v1/status"] = route { server, request in
            server.withAuthenticatedDevice(request) { _ in server.handleStatus() }
        }
        httpServer.GET["/api/v1/findings"] = route { server, request in
            server.withAuthenticatedDevice(request) { _ in server.handleFindings() }
        }
        httpServer.POST["/api/v1/findings/:findingID/approval-requests"] = route { server, request in
            server.withAuthenticatedDevice(request) { device in
                server.handleCreateApprovalRequest(request, device: device)
            }
        }
        httpServer.GET["/api/v1/approval-requests"] = route { server, request in
            server.withAuthenticatedDevice(request) { _ in server.handleListApprovalRequests(request) }
        }
        httpServer.GET["/api/v1/approval-requests/:id"] = route { server, request in
            server.withAuthenticatedDevice(request) { _ in server.handleGetApprovalRequest(request) }
        }
        httpServer.POST["/api/v1/approval-requests/:id/fulfill"] = route { server, request in
            server.withAuthenticatedDevice(request) { device in
                server.handleFulfillApprovalRequest(request, device: device)
            }
        }

        if let staticFileRoot {
            registerStaticFiles(root: staticFileRoot)
        }
    }

    /// Captures `self` weakly once so individual route closures stay terse
    /// (`route { server, request in ... }`) instead of each repeating
    /// `[weak self]` + optional-chaining boilerplate. Avoids a retain cycle
    /// between `httpServer`'s router (owned by `self`) and `self`.
    private func route(_ handler: @escaping (RemoteControlServer, HttpRequest) -> HttpResponse) -> (HttpRequest) -> HttpResponse {
        { [weak self] request in
            guard let self else { return .internalServerError }
            return handler(self, request)
        }
    }

    private func registerStaticFiles(root: URL) {
        let handler = StaticFileServing.handler(root: root)
        // Registered explicitly under `GET` (static assets are never
        // mutated by POST/etc.), one concrete route per file discovered
        // under `root` — see `StaticFileServing`'s doc comment for why this
        // enumerates files instead of registering a wildcard route.
        httpServer.GET["/"] = handler
        // `PairingInvitation.pairingURL(host:port:)` points at `/pair`
        // (e.g. the QR code's URL). Alias it to serve `index.html`'s
        // content too — note this reassigns `request.path` to "/" rather
        // than just pointing at `handler` directly, since `handler` looks
        // up a file matching the *actual* request path and there's no file
        // literally named "pair" on disk. The page reads `?token=...` from
        // `location.search` client-side to prefill the pairing form (see
        // `RemoteWebApp/src/app.js`).
        httpServer.GET["/pair"] = { request in
            request.path = "/"
            return handler(request)
        }
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else { return }
        let rootPath = root.standardizedFileURL.path
        for case let fileURL as URL in enumerator {
            guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            let filePath = fileURL.standardizedFileURL.path
            guard filePath.hasPrefix(rootPath) else { continue }
            let routePath = String(filePath.dropFirst(rootPath.count))
            httpServer.GET[routePath.hasPrefix("/") ? routePath : "/" + routePath] = handler
        }
    }

    // MARK: - Transport guards (LAN scoping, body size, rate limit)

    private func enforceTransportGuards(for request: HttpRequest) -> HttpResponse? {
        guard LANGuard.isLANOrLocalAddress(request.address) else {
            return .forbidden
        }

        let currentSettings = settings
        // Best-effort: Swifter's parser has already read the full body off
        // the socket by the time a handler (or this middleware) runs, so
        // this doesn't prevent the read — it prevents *processing* an
        // oversized body any further. See `RemoteControlSettings
        // .maxRequestBodyBytes`.
        guard request.body.count <= currentSettings.maxRequestBodyBytes else {
            return errorResponse(
                413, "Payload Too Large", code: "payload_too_large",
                message: "Request body exceeds the \(currentSettings.maxRequestBodyBytes)-byte limit."
            )
        }

        guard rateLimiter.allow(request.address ?? "unknown") else {
            return errorResponse(429, "Too Many Requests", code: "rate_limited", message: "Too many requests; slow down.")
        }

        return nil
    }

    // MARK: - Auth

    private func withAuthenticatedDevice(_ request: HttpRequest, _ handler: (PairedDevice) -> HttpResponse) -> HttpResponse {
        guard let token = bearerToken(from: request) else {
            return errorResponse(401, "Unauthorized", code: "missing_token", message: "Missing or malformed Authorization header.")
        }
        let tokenHash = TokenGenerator.hash(token)
        guard let device = runBlocking({ await self.pairingStore.device(forTokenHash: tokenHash) }) else {
            return errorResponse(401, "Unauthorized", code: "invalid_token", message: "Token is invalid, revoked, or unknown.")
        }
        return handler(device)
    }

    private func bearerToken(from request: HttpRequest) -> String? {
        guard let header = request.headers["authorization"] else { return nil }
        let prefix = "Bearer "
        guard header.hasPrefix(prefix) else { return nil }
        let token = String(header.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        return token.isEmpty ? nil : token
    }

    // MARK: - Endpoint handlers

    private struct HealthDTO: Encodable { let status: String; let apiVersion: Int }
    private func handleHealth() -> HttpResponse {
        jsonResponse(HealthDTO(status: "ok", apiVersion: Self.apiVersion))
    }

    private struct PairRequestBody: Decodable { let pairingToken: String; let deviceName: String? }
    private struct PairResponseBody: Encodable {
        let deviceID: UUID
        let deviceToken: String
        let deviceName: String
        let pairedAt: Date
        let apiVersion: Int
    }
    private func handlePair(_ request: HttpRequest) -> HttpResponse {
        guard let body = decodeBody(PairRequestBody.self, from: request) else {
            return errorResponse(400, "Bad Request", code: "invalid_body", message: "Expected JSON {\"pairingToken\": \"...\"}.")
        }
        let invitationHash = TokenGenerator.hash(body.pairingToken)
        let redeemed = runBlocking { await self.pairingStore.consumeInvitation(tokenHash: invitationHash, now: Date()) }
        guard redeemed != nil else {
            return errorResponse(
                401, "Unauthorized", code: "invalid_pairing_token",
                message: "Pairing token is invalid, expired, or already used."
            )
        }

        let deviceToken = TokenGenerator.generateToken()
        let trimmedName = body.deviceName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let displayName = trimmedName.isEmpty ? "Paired device" : trimmedName
        let device = PairedDevice(displayName: displayName, tokenHash: TokenGenerator.hash(deviceToken))
        runBlocking { await self.pairingStore.saveDevice(device) }

        return jsonResponse(
            PairResponseBody(
                deviceID: device.id,
                deviceToken: deviceToken,
                deviceName: device.displayName,
                pairedAt: device.pairedAt,
                apiVersion: Self.apiVersion
            ),
            status: 201, reason: "Created"
        )
    }

    private struct RevokedDTO: Encodable { let revoked: Bool }
    private func handleSelfRevoke(device: PairedDevice) -> HttpResponse {
        runBlocking { await self.pairingStore.revokeDevice(id: device.id) }
        return jsonResponse(RevokedDTO(revoked: true))
    }

    private struct StatusDTO: Encodable {
        let apiVersion: Int
        let serverTime: Date
        let disk: DiskStatus
        let lastScanStartedAt: Date?
        let lastScanFinishedAt: Date?
        let findingsCount: Int
        let totalReclaimableBytes: Int64
        let quarantineActiveCount: Int
    }
    private func handleStatus() -> HttpResponse {
        let snapshot = runBlocking { await self.scanSnapshotProvider.currentSnapshot() }
        let disk = diskSpaceProvider.diskStatus()
        let activeReceipts = runBlocking { (try? await self.quarantineManager.listActive()) ?? [] }
        let reclaimable = snapshot.findings.reduce(Int64(0)) { $0 + ($1.item.sizeBytes ?? 0) }
        return jsonResponse(StatusDTO(
            apiVersion: Self.apiVersion,
            serverTime: Date(),
            disk: disk,
            lastScanStartedAt: snapshot.lastScanStartedAt,
            lastScanFinishedAt: snapshot.lastScanFinishedAt,
            findingsCount: snapshot.findings.count,
            totalReclaimableBytes: reclaimable,
            quarantineActiveCount: activeReceipts.count
        ))
    }

    private struct FindingsResponseDTO: Encodable { let generatedAt: Date; let findings: [ScanFinding] }
    private func handleFindings() -> HttpResponse {
        let snapshot = runBlocking { await self.scanSnapshotProvider.currentSnapshot() }
        return jsonResponse(FindingsResponseDTO(generatedAt: Date(), findings: snapshot.findings))
    }

    private func handleCreateApprovalRequest(_ request: HttpRequest, device: PairedDevice) -> HttpResponse {
        // Swifter's router stores path-variable values keyed by the raw
        // registered segment, colon included (see HttpRouter.swift /
        // SwifterTestsHttpRouter's own `params[":arg1"]` assertions) — so
        // this must look up ":findingID", not "findingID".
        guard let findingIDString = request.params[":findingID"], let findingID = UUID(uuidString: findingIDString) else {
            return errorResponse(400, "Bad Request", code: "invalid_finding_id", message: "findingID must be a UUID.")
        }
        let snapshot = runBlocking { await self.scanSnapshotProvider.currentSnapshot() }
        guard let finding = snapshot.findings.first(where: { $0.id == findingID }) else {
            return errorResponse(404, "Not Found", code: "finding_not_found", message: "No current finding with that id.")
        }
        if case .forbidden = finding.verdict {
            return errorResponse(
                409, "Conflict", code: "forbidden_item",
                message: "This item matches the hardcoded denylist and can never be quarantined."
            )
        }
        if let existing = runBlocking({ await self.approvalStore.existingPending(forFindingID: findingID) }) {
            return jsonResponse(existing)
        }
        let created = runBlocking { await self.approvalStore.create(findingID: findingID, requestedByDeviceID: device.id) }
        return jsonResponse(created, status: 201, reason: "Created")
    }

    private struct ApprovalRequestListDTO: Encodable { let approvalRequests: [ApprovalRequest] }
    private func handleListApprovalRequests(_ request: HttpRequest) -> HttpResponse {
        let statusRaw = request.queryParams.first(where: { $0.0 == "status" })?.1
        let statusFilter = statusRaw.flatMap(ApprovalStatus.init(rawValue:))
        let items = runBlocking { await self.approvalStore.all(status: statusFilter) }
        return jsonResponse(ApprovalRequestListDTO(approvalRequests: items))
    }

    private func handleGetApprovalRequest(_ request: HttpRequest) -> HttpResponse {
        // See the ":findingID" comment above — Swifter keeps the colon.
        guard let idString = request.params[":id"], let id = UUID(uuidString: idString) else {
            return errorResponse(400, "Bad Request", code: "invalid_id", message: "id must be a UUID.")
        }
        guard let item = runBlocking({ await self.approvalStore.get(id) }) else {
            return errorResponse(404, "Not Found", code: "approval_request_not_found", message: "No approval request with that id.")
        }
        return jsonResponse(item)
    }

    private struct FulfillRequestBody: Decodable { let decision: ApprovalDecision }
    private func handleFulfillApprovalRequest(_ request: HttpRequest, device: PairedDevice) -> HttpResponse {
        guard let idString = request.params[":id"], let id = UUID(uuidString: idString) else {
            return errorResponse(400, "Bad Request", code: "invalid_id", message: "id must be a UUID.")
        }
        guard let body = decodeBody(FulfillRequestBody.self, from: request) else {
            return errorResponse(400, "Bad Request", code: "invalid_body", message: "Expected JSON {\"decision\": \"approve\"|\"reject\"}.")
        }
        if body.decision == .approve, !settings.allowMobileApprovalFulfillment {
            return errorResponse(
                403, "Forbidden", code: "mobile_fulfillment_disabled",
                message: "This Mac has not enabled mobile-initiated approval. Approve from the Mac app instead."
            )
        }

        let result = runBlocking {
            await self.resolveApprovalRequest(id: id, decision: body.decision, actor: .device(device.id))
        }
        switch result {
        case .success(let approval):
            return jsonResponse(approval)
        case .failure(.notFound):
            return errorResponse(404, "Not Found", code: "approval_request_not_found", message: "No approval request with that id.")
        case .failure(.alreadyResolved):
            return errorResponse(409, "Conflict", code: "already_resolved", message: "This approval request was already resolved.")
        case .failure(.findingMissing), .failure(.forbiddenItem), .failure(.quarantineFailed):
            // Persisted as `.failed` on the approval request itself (with
            // `failureReason` set) so the client can see why, rather than
            // just getting a bare error.
            if let approval = runBlocking({ await self.approvalStore.get(id) }) {
                return jsonResponse(approval)
            }
            return errorResponse(500, "Internal Server Error", code: "resolve_failed", message: "Failed to resolve approval request.")
        }
    }

    // MARK: - Shared resolve logic (desktop in-process path + mobile HTTP path)

    private enum ResolveApprovalError: Error {
        case notFound
        case alreadyResolved
        case findingMissing
        case forbiddenItem
        case quarantineFailed(String)
    }

    /// The single place that ever calls `QuarantineManaging.quarantine`.
    /// Both `fulfillApprovalRequest` (desktop, in-process) and
    /// `handleFulfillApprovalRequest` (mobile, HTTP, gated by
    /// `allowMobileApprovalFulfillment`) funnel through here.
    private func resolveApprovalRequest(
        id: UUID,
        decision: ApprovalDecision,
        actor: ApprovalActor
    ) async -> Result<ApprovalRequest, ResolveApprovalError> {
        guard var approval = await approvalStore.get(id) else { return .failure(.notFound) }
        guard approval.status == .pending else { return .failure(.alreadyResolved) }

        if decision == .reject {
            approval.status = .rejected
            approval.resolvedAt = Date()
            approval.resolvedBy = actor
            await approvalStore.update(approval)
            return .success(approval)
        }

        let snapshot = await scanSnapshotProvider.currentSnapshot()
        guard let finding = snapshot.findings.first(where: { $0.id == approval.findingID }) else {
            approval.status = .failed
            approval.resolvedAt = Date()
            approval.resolvedBy = actor
            approval.failureReason = "Finding is no longer present in the current scan snapshot."
            await approvalStore.update(approval)
            return .failure(.findingMissing)
        }
        // Defense in depth: re-check the verdict at resolve time too, not
        // just at request-creation time — the snapshot could have changed
        // (a rescan re-classified it) in between.
        if case .forbidden = finding.verdict {
            approval.status = .failed
            approval.resolvedAt = Date()
            approval.resolvedBy = actor
            approval.failureReason = "Item matches the hardcoded denylist."
            await approvalStore.update(approval)
            return .failure(.forbiddenItem)
        }

        do {
            let receipt = try await quarantineManager.quarantine(finding.item, retention: .default)
            approval.status = .fulfilled
            approval.resolvedAt = Date()
            approval.resolvedBy = actor
            approval.quarantineReceiptID = receipt.id
            await approvalStore.update(approval)
            return .success(approval)
        } catch {
            approval.status = .failed
            approval.resolvedAt = Date()
            approval.resolvedBy = actor
            approval.failureReason = String(describing: error)
            await approvalStore.update(approval)
            return .failure(.quarantineFailed(String(describing: error)))
        }
    }
}
