import CoreScanEngine
import Foundation
import SafetyRules
import XCTest
@testable import RemoteControlServer

/// Integration tests that spin up a real `RemoteControlServer` (real
/// Swifter `HttpServer`, real BSD sockets) on an ephemeral port (`0`) and
/// exercise it with real `URLSession` requests over loopback — no mocked
/// HTTP layer.
final class RemoteControlServerIntegrationTests: XCTestCase {
    private func makeServer(
        settings: RemoteControlSettings = RemoteControlSettings()
    ) throws -> (server: RemoteControlServer, provider: FixtureScanSnapshotProvider, quarantine: FixtureQuarantineManager, port: UInt16) {
        let snapshot = ScanSnapshot(
            lastScanStartedAt: Date(),
            lastScanFinishedAt: Date(),
            findings: [Fixture.needsConfirmationFinding(), Fixture.forbiddenFinding()]
        )
        let provider = FixtureScanSnapshotProvider(snapshot: snapshot)
        let quarantine = FixtureQuarantineManager()
        let disk = FixtureDiskSpaceProvider(status: DiskStatus(freeBytes: 111, totalBytes: 222))
        let server = RemoteControlServer(
            scanSnapshotProvider: provider,
            quarantineManager: quarantine,
            diskSpaceProvider: disk,
            pairingStore: InMemoryPairingStore(),
            settings: settings
        )
        let boundPort = try server.start(port: 0)
        return (server, provider, quarantine, boundPort)
    }

    private func baseURL(port: UInt16) -> URL {
        URL(string: "http://127.0.0.1:\(port)")!
    }

    private func number(_ dict: [String: Any]?, _ key: String) -> Int64? {
        (dict?[key] as? NSNumber)?.int64Value
    }

    // MARK: - health / auth

    func testHealthDoesNotRequireAuth() async throws {
        let fixture = try makeServer()
        defer { fixture.server.stop() }

        let (data, response) = try await URLSession.shared.data(
            from: baseURL(port: fixture.port).appendingPathComponent("api/v1/health")
        )
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?["status"] as? String, "ok")
        XCTAssertEqual(number(json, "apiVersion"), 1)
    }

    func testStatusWithoutTokenIsRejected() async throws {
        let fixture = try makeServer()
        defer { fixture.server.stop() }

        let (_, response) = try await URLSession.shared.data(
            from: baseURL(port: fixture.port).appendingPathComponent("api/v1/status")
        )
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 401)
    }

    func testStatusWithInvalidTokenIsRejected() async throws {
        let fixture = try makeServer()
        defer { fixture.server.stop() }

        var request = URLRequest(url: baseURL(port: fixture.port).appendingPathComponent("api/v1/status"))
        request.addValue("Bearer not-a-real-token", forHTTPHeaderField: "Authorization")
        let (_, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 401)
    }

    // MARK: - pairing

    func testPairingFlowAndAuthenticatedStatus() async throws {
        let fixture = try makeServer()
        defer { fixture.server.stop() }

        // A bogus pairing token is rejected.
        do {
            var badRequest = URLRequest(url: baseURL(port: fixture.port).appendingPathComponent("api/v1/pair"))
            badRequest.httpMethod = "POST"
            badRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            badRequest.httpBody = try JSONSerialization.data(withJSONObject: ["pairingToken": "bogus"])
            let (_, response) = try await URLSession.shared.data(for: badRequest)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 401)
        }

        // Desktop generates a real invitation; mobile redeems it.
        let invitation = await fixture.server.beginPairing()

        var pairRequest = URLRequest(url: baseURL(port: fixture.port).appendingPathComponent("api/v1/pair"))
        pairRequest.httpMethod = "POST"
        pairRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        pairRequest.httpBody = try JSONSerialization.data(
            withJSONObject: ["pairingToken": invitation.token, "deviceName": "Test iPhone"]
        )
        let (pairData, pairResponse) = try await URLSession.shared.data(for: pairRequest)
        XCTAssertEqual((pairResponse as? HTTPURLResponse)?.statusCode, 201)
        let pairJSON = try JSONSerialization.jsonObject(with: pairData) as? [String: Any]
        let deviceToken = try XCTUnwrap(pairJSON?["deviceToken"] as? String)
        XCTAssertEqual(pairJSON?["deviceName"] as? String, "Test iPhone")

        // The same pairing token can never be redeemed twice.
        var replay = URLRequest(url: baseURL(port: fixture.port).appendingPathComponent("api/v1/pair"))
        replay.httpMethod = "POST"
        replay.setValue("application/json", forHTTPHeaderField: "Content-Type")
        replay.httpBody = try JSONSerialization.data(withJSONObject: ["pairingToken": invitation.token])
        let (_, replayResponse) = try await URLSession.shared.data(for: replay)
        XCTAssertEqual((replayResponse as? HTTPURLResponse)?.statusCode, 401)

        // The freshly issued device token authenticates.
        var statusRequest = URLRequest(url: baseURL(port: fixture.port).appendingPathComponent("api/v1/status"))
        statusRequest.addValue("Bearer \(deviceToken)", forHTTPHeaderField: "Authorization")
        let (statusData, statusResponse) = try await URLSession.shared.data(for: statusRequest)
        XCTAssertEqual((statusResponse as? HTTPURLResponse)?.statusCode, 200)
        let statusJSON = try JSONSerialization.jsonObject(with: statusData) as? [String: Any]
        let disk = statusJSON?["disk"] as? [String: Any]
        XCTAssertEqual(number(disk, "freeBytes"), 111)
        XCTAssertEqual(number(disk, "totalBytes"), 222)
        XCTAssertEqual(number(statusJSON, "findingsCount"), 2)
    }

    func testSelfRevokeInvalidatesToken() async throws {
        let fixture = try makeServer()
        defer { fixture.server.stop() }
        let deviceToken = try await pairNewDevice(server: fixture.server, port: fixture.port)

        var revokeRequest = URLRequest(url: baseURL(port: fixture.port).appendingPathComponent("api/v1/pair/revoke"))
        revokeRequest.httpMethod = "POST"
        revokeRequest.addValue("Bearer \(deviceToken)", forHTTPHeaderField: "Authorization")
        let (_, revokeResponse) = try await URLSession.shared.data(for: revokeRequest)
        XCTAssertEqual((revokeResponse as? HTTPURLResponse)?.statusCode, 200)

        var statusRequest = URLRequest(url: baseURL(port: fixture.port).appendingPathComponent("api/v1/status"))
        statusRequest.addValue("Bearer \(deviceToken)", forHTTPHeaderField: "Authorization")
        let (_, statusResponse) = try await URLSession.shared.data(for: statusRequest)
        XCTAssertEqual((statusResponse as? HTTPURLResponse)?.statusCode, 401)
    }

    // MARK: - findings + approval flow

    func testFindingsListsFixtureItems() async throws {
        let fixture = try makeServer()
        defer { fixture.server.stop() }
        let token = try await pairNewDevice(server: fixture.server, port: fixture.port)

        var request = URLRequest(url: baseURL(port: fixture.port).appendingPathComponent("api/v1/findings"))
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let findings = json?["findings"] as? [[String: Any]]
        XCTAssertEqual(findings?.count, 2)
    }

    func testApprovalRequestRejectedForForbiddenItem() async throws {
        let fixture = try makeServer()
        defer { fixture.server.stop() }
        let token = try await pairNewDevice(server: fixture.server, port: fixture.port)
        let forbiddenID = fixture.provider.snapshot.findings.first {
            if case .forbidden = $0.verdict { return true }
            return false
        }!.id

        var request = URLRequest(
            url: baseURL(port: fixture.port).appendingPathComponent("api/v1/findings/\(forbiddenID)/approval-requests")
        )
        request.httpMethod = "POST"
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 409)
    }

    func testApprovalRequestAndDesktopFulfillment() async throws {
        let fixture = try makeServer()
        defer { fixture.server.stop() }
        let token = try await pairNewDevice(server: fixture.server, port: fixture.port)
        let findingID = fixture.provider.snapshot.findings.first {
            if case .needsConfirmation = $0.verdict { return true }
            return false
        }!.id

        var createRequest = URLRequest(
            url: baseURL(port: fixture.port).appendingPathComponent("api/v1/findings/\(findingID)/approval-requests")
        )
        createRequest.httpMethod = "POST"
        createRequest.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (createData, createResponse) = try await URLSession.shared.data(for: createRequest)
        XCTAssertEqual((createResponse as? HTTPURLResponse)?.statusCode, 201)
        let createJSON = try JSONSerialization.jsonObject(with: createData) as? [String: Any]
        let approvalIDString = try XCTUnwrap(createJSON?["id"] as? String)
        let approvalID = try XCTUnwrap(UUID(uuidString: approvalIDString))

        // A mobile client attempting to fulfill directly is blocked by the
        // default (off) `allowMobileApprovalFulfillment` setting.
        var fulfillRequest = URLRequest(
            url: baseURL(port: fixture.port).appendingPathComponent("api/v1/approval-requests/\(approvalID)/fulfill")
        )
        fulfillRequest.httpMethod = "POST"
        fulfillRequest.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        fulfillRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        fulfillRequest.httpBody = try JSONSerialization.data(withJSONObject: ["decision": "approve"])
        let (_, fulfillResponse) = try await URLSession.shared.data(for: fulfillRequest)
        XCTAssertEqual((fulfillResponse as? HTTPURLResponse)?.statusCode, 403)

        // The desktop app fulfills in-process instead (never over HTTP).
        let resolved = await fixture.server.fulfillApprovalRequest(id: approvalID, decision: .approve)
        XCTAssertEqual(resolved?.status, .fulfilled)
        let quarantined = await fixture.quarantine.quarantinedItems
        XCTAssertEqual(quarantined.count, 1)
    }

    func testMobileFulfillmentAllowedWhenSettingEnabled() async throws {
        let fixture = try makeServer(settings: RemoteControlSettings(allowMobileApprovalFulfillment: true))
        defer { fixture.server.stop() }
        let token = try await pairNewDevice(server: fixture.server, port: fixture.port)
        let findingID = fixture.provider.snapshot.findings.first {
            if case .needsConfirmation = $0.verdict { return true }
            return false
        }!.id

        var createRequest = URLRequest(
            url: baseURL(port: fixture.port).appendingPathComponent("api/v1/findings/\(findingID)/approval-requests")
        )
        createRequest.httpMethod = "POST"
        createRequest.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (createData, _) = try await URLSession.shared.data(for: createRequest)
        let createJSON = try JSONSerialization.jsonObject(with: createData) as? [String: Any]
        let approvalID = try XCTUnwrap(createJSON?["id"] as? String)

        var fulfillRequest = URLRequest(
            url: baseURL(port: fixture.port).appendingPathComponent("api/v1/approval-requests/\(approvalID)/fulfill")
        )
        fulfillRequest.httpMethod = "POST"
        fulfillRequest.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        fulfillRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        fulfillRequest.httpBody = try JSONSerialization.data(withJSONObject: ["decision": "approve"])
        let (fulfillData, fulfillResponse) = try await URLSession.shared.data(for: fulfillRequest)
        XCTAssertEqual((fulfillResponse as? HTTPURLResponse)?.statusCode, 200)
        let fulfillJSON = try JSONSerialization.jsonObject(with: fulfillData) as? [String: Any]
        XCTAssertEqual(fulfillJSON?["status"] as? String, "fulfilled")
        let quarantined = await fixture.quarantine.quarantinedItems
        XCTAssertEqual(quarantined.count, 1)
    }

    func testRejectingApprovalRequestNeverCallsQuarantine() async throws {
        let fixture = try makeServer(settings: RemoteControlSettings(allowMobileApprovalFulfillment: true))
        defer { fixture.server.stop() }
        let token = try await pairNewDevice(server: fixture.server, port: fixture.port)
        let findingID = fixture.provider.snapshot.findings.first {
            if case .needsConfirmation = $0.verdict { return true }
            return false
        }!.id

        var createRequest = URLRequest(
            url: baseURL(port: fixture.port).appendingPathComponent("api/v1/findings/\(findingID)/approval-requests")
        )
        createRequest.httpMethod = "POST"
        createRequest.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (createData, _) = try await URLSession.shared.data(for: createRequest)
        let createJSON = try JSONSerialization.jsonObject(with: createData) as? [String: Any]
        let approvalID = try XCTUnwrap(createJSON?["id"] as? String)

        var fulfillRequest = URLRequest(
            url: baseURL(port: fixture.port).appendingPathComponent("api/v1/approval-requests/\(approvalID)/fulfill")
        )
        fulfillRequest.httpMethod = "POST"
        fulfillRequest.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        fulfillRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        fulfillRequest.httpBody = try JSONSerialization.data(withJSONObject: ["decision": "reject"])
        let (fulfillData, fulfillResponse) = try await URLSession.shared.data(for: fulfillRequest)
        XCTAssertEqual((fulfillResponse as? HTTPURLResponse)?.statusCode, 200)
        let fulfillJSON = try JSONSerialization.jsonObject(with: fulfillData) as? [String: Any]
        XCTAssertEqual(fulfillJSON?["status"] as? String, "rejected")
        let quarantined = await fixture.quarantine.quarantinedItems
        XCTAssertTrue(quarantined.isEmpty)
    }

    // MARK: - static file serving

    func testServesStaticFiles() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir.appendingPathComponent("src"), withIntermediateDirectories: true)
        try "<html>hello</html>".write(to: tempDir.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        try "console.log('hi')".write(to: tempDir.appendingPathComponent("src/app.js"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let provider = FixtureScanSnapshotProvider(snapshot: .empty)
        let server = RemoteControlServer(
            scanSnapshotProvider: provider,
            quarantineManager: FixtureQuarantineManager(),
            staticFileRoot: tempDir
        )
        let port = try server.start(port: 0)
        defer { server.stop() }

        let (rootData, rootResponse) = try await URLSession.shared.data(from: baseURL(port: port))
        XCTAssertEqual((rootResponse as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(String(data: rootData, encoding: .utf8), "<html>hello</html>")

        let (jsData, jsResponse) = try await URLSession.shared.data(
            from: baseURL(port: port).appendingPathComponent("src/app.js")
        )
        XCTAssertEqual((jsResponse as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(String(data: jsData, encoding: .utf8), "console.log('hi')")

        // Regression: `/pair` (the path `PairingInvitation.pairingURL`
        // points a QR code at) must serve the same `index.html` content,
        // not 404 by trying to find a literal file named "pair" on disk.
        let (pairData, pairResponse) = try await URLSession.shared.data(
            from: baseURL(port: port).appendingPathComponent("pair")
        )
        XCTAssertEqual((pairResponse as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(String(data: pairData, encoding: .utf8), "<html>hello</html>")
    }

    // MARK: - helpers

    private func pairNewDevice(server: RemoteControlServer, port: UInt16) async throws -> String {
        let invitation = await server.beginPairing()
        var request = URLRequest(url: baseURL(port: port).appendingPathComponent("api/v1/pair"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["pairingToken": invitation.token, "deviceName": "Test Device"]
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 201)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return try XCTUnwrap(json?["deviceToken"] as? String)
    }
}
