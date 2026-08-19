import Foundation
import XCTest
@testable import VirusTotalClient

/// All requests in this file are intercepted by `MockURLProtocol` -- nothing
/// here ever reaches virustotal.com. Every client under test is built with a
/// generous, fake-clock-backed `VirusTotalRateLimiter` so a test never
/// blocks on the limiter's real wait/backoff behavior (that's covered
/// separately in `VirusTotalRateLimiterTests`).
final class RealVirusTotalClientTests: XCTestCase {
    private let sha256 = "d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2"

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    private func fastRateLimiter() -> VirusTotalRateLimiter {
        let clock = TestClock()
        return VirusTotalRateLimiter(
            limits: .init(requestsPerMinute: 1000, requestsPerDay: 1000),
            clock: clock,
            sleeper: FakeSleeper(clock: clock)
        )
    }

    private func makeClient(apiKey: String? = "test-api-key") -> RealVirusTotalClient {
        let clock = TestClock()
        return RealVirusTotalClient(
            apiKey: apiKey,
            session: makeMockedSession(),
            rateLimiter: fastRateLimiter(),
            sleeper: FakeSleeper(clock: clock),
            analysisPollInterval: 1,
            analysisPollAttempts: 3
        )
    }

    // MARK: - isConfigured

    func testIsConfigured_withKey_isTrue() {
        XCTAssertTrue(makeClient(apiKey: "abc").isConfigured)
    }

    func testIsConfigured_withNilKey_isFalse() {
        XCTAssertFalse(makeClient(apiKey: nil).isConfigured)
    }

    func testIsConfigured_withEmptyKey_isFalse() {
        XCTAssertFalse(makeClient(apiKey: "   ").isConfigured)
    }

    // MARK: - not configured

    func testLookupHash_notConfigured_throwsImmediatelyWithNoRequest() async {
        let client = makeClient(apiKey: nil)
        do {
            _ = try await client.lookupHash(sha256)
            XCTFail("expected notConfigured to be thrown")
        } catch VirusTotalClientError.notConfigured {
            // expected
        } catch {
            XCTFail("expected .notConfigured, got \(error)")
        }
        XCTAssertEqual(MockURLProtocol.recordedRequestCount, 0, "no request should be attempted without a configured key")
    }

    func testUploadFile_notConfigured_throwsImmediatelyWithNoRequest() async throws {
        let client = makeClient(apiKey: nil)
        let path = try makeTempFile(contents: "hello")
        do {
            _ = try await client.uploadFile(at: path, consentGiven: true)
            XCTFail("expected notConfigured to be thrown")
        } catch VirusTotalClientError.notConfigured {
            // expected
        } catch {
            XCTFail("expected .notConfigured, got \(error)")
        }
        XCTAssertEqual(MockURLProtocol.recordedRequestCount, 0)
    }

    // MARK: - lookupHash

    func testLookupHash_success_parsesReport() async throws {
        let client = makeClient()
        let expectedHash = sha256
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-apikey"), "test-api-key")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertTrue(request.url?.absoluteString.contains("/files/\(expectedHash)") ?? false)
            let body = """
            {
              "data": {
                "id": "\(expectedHash)",
                "type": "file",
                "links": { "self": "https://www.virustotal.com/api/v3/files/\(expectedHash)" },
                "attributes": {
                  "last_analysis_stats": {
                    "malicious": 2,
                    "suspicious": 1,
                    "harmless": 60,
                    "undetected": 10
                  }
                }
              }
            }
            """
            return .success(.init(statusCode: 200, data: Data(body.utf8)))
        }

        let report = try await client.lookupHash(sha256)
        let unwrapped = try XCTUnwrap(report)
        XCTAssertEqual(unwrapped.sha256, sha256)
        XCTAssertEqual(unwrapped.maliciousCount, 2)
        XCTAssertEqual(unwrapped.suspiciousCount, 1)
        XCTAssertEqual(unwrapped.harmlessCount, 60)
        XCTAssertEqual(unwrapped.undetectedCount, 10)
        XCTAssertEqual(unwrapped.permalink, URL(string: "https://www.virustotal.com/api/v3/files/\(sha256)"))
        XCTAssertEqual(MockURLProtocol.recordedRequestCount, 1)
    }

    func testLookupHash_success_missingLinksFallsBackToGUIPermalink() async throws {
        let client = makeClient()
        MockURLProtocol.handler = { _ in
            let body = """
            {
              "data": {
                "attributes": {
                  "last_analysis_stats": { "malicious": 0, "suspicious": 0, "harmless": 5, "undetected": 1 }
                }
              }
            }
            """
            return .success(.init(statusCode: 200, data: Data(body.utf8)))
        }

        let report = try await client.lookupHash(sha256)
        let unwrapped = try XCTUnwrap(report)
        XCTAssertEqual(unwrapped.permalink, URL(string: "https://www.virustotal.com/gui/file/\(sha256)"))
    }

    func testLookupHash_404_returnsNilNotError() async throws {
        let client = makeClient()
        MockURLProtocol.handler = { _ in
            .success(.init(statusCode: 404, data: Data("{}".utf8)))
        }

        let report = try await client.lookupHash(sha256)
        XCTAssertNil(report)
    }

    func testLookupHash_nonSuccessStatus_throwsTypedRequestFailedError() async {
        let client = makeClient()
        MockURLProtocol.handler = { _ in
            let body = """
            {"error": {"code": "WrongCredentialsError", "message": "Wrong API key"}}
            """
            return .success(.init(statusCode: 403, data: Data(body.utf8)))
        }

        do {
            _ = try await client.lookupHash(sha256)
            XCTFail("expected requestFailed to be thrown")
        } catch VirusTotalClientError.requestFailed(let statusCode, let message) {
            XCTAssertEqual(statusCode, 403)
            XCTAssertEqual(message, "WrongCredentialsError: Wrong API key")
        } catch {
            XCTFail("expected .requestFailed, got \(error)")
        }
    }

    func testLookupHash_invalidHash_throwsWithoutRequest() async {
        let client = makeClient()
        do {
            _ = try await client.lookupHash("not-a-hash")
            XCTFail("expected invalidHash to be thrown")
        } catch VirusTotalClientError.invalidHash {
            // expected
        } catch {
            XCTFail("expected .invalidHash, got \(error)")
        }
        XCTAssertEqual(MockURLProtocol.recordedRequestCount, 0)
    }

    // MARK: - uploadFile consent enforcement

    func testUploadFile_consentFalse_throwsImmediatelyWithNoRequestAtAll() async throws {
        let client = makeClient()
        let path = try makeTempFile(contents: "some file contents")

        do {
            _ = try await client.uploadFile(at: path, consentGiven: false)
            XCTFail("expected consentRequired to be thrown")
        } catch VirusTotalClientError.consentRequired {
            // expected
        } catch {
            XCTFail("expected .consentRequired, got \(error)")
        }

        XCTAssertEqual(MockURLProtocol.recordedRequestCount, 0, "zero requests -- not even a HEAD request -- should happen without consent")
    }

    // MARK: - uploadFile with consent

    func testUploadFile_consentTrue_success_pollsUntilCompleted() async throws {
        let client = makeClient()
        let path = try makeTempFile(contents: "some file contents")
        let analysisPollCount = LockedCounter()

        MockURLProtocol.handler = { request in
            guard let url = request.url else { return .failure(URLError(.badURL)) }
            if url.path.hasSuffix("/files") {
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")?.contains("multipart/form-data") ?? false)
                let body = """
                {"data": {"id": "analysis-123", "type": "analysis"}}
                """
                return .success(.init(statusCode: 200, data: Data(body.utf8)))
            }
            if url.path.contains("/analyses/analysis-123") {
                let count = analysisPollCount.increment()
                if count < 2 {
                    let body = """
                    {"data": {"id": "analysis-123", "type": "analysis", "attributes": {"status": "queued"}}}
                    """
                    return .success(.init(statusCode: 200, data: Data(body.utf8)))
                }
                let body = """
                {"data": {"id": "analysis-123", "type": "analysis", "attributes": {"status": "completed", "stats": {"malicious": 0, "suspicious": 0, "harmless": 65, "undetected": 5}}}}
                """
                return .success(.init(statusCode: 200, data: Data(body.utf8)))
            }
            XCTFail("unexpected request to \(url)")
            return .failure(URLError(.badURL))
        }

        let report = try await client.uploadFile(at: path, consentGiven: true)
        XCTAssertEqual(report.harmlessCount, 65)
        XCTAssertEqual(report.undetectedCount, 5)
        XCTAssertEqual(report.maliciousCount, 0)
        XCTAssertEqual(analysisPollCount.value, 2)
        XCTAssertNotNil(report.permalink)
    }

    func testUploadFile_analysisNeverCompletes_returnsBestEffortReportAfterBoundedPolling() async throws {
        let client = makeClient()
        let path = try makeTempFile(contents: "some file contents")

        MockURLProtocol.handler = { request in
            guard let url = request.url else { return .failure(URLError(.badURL)) }
            if url.path.hasSuffix("/files") {
                let body = """
                {"data": {"id": "analysis-999", "type": "analysis"}}
                """
                return .success(.init(statusCode: 200, data: Data(body.utf8)))
            }
            let body = """
            {"data": {"id": "analysis-999", "type": "analysis", "attributes": {"status": "queued"}}}
            """
            return .success(.init(statusCode: 200, data: Data(body.utf8)))
        }

        let report = try await client.uploadFile(at: path, consentGiven: true)
        // Bounded polling gave up -- best-effort report, not an error, and not
        // mistakable for a real "harmless" verdict except by its zeroed stats.
        XCTAssertEqual(report.maliciousCount, 0)
        XCTAssertEqual(report.harmlessCount, 0)
        XCTAssertEqual(report.undetectedCount, 0)
        XCTAssertNotNil(report.permalink)

        // 1 upload request + 3 poll attempts (analysisPollAttempts: 3).
        XCTAssertEqual(MockURLProtocol.recordedRequestCount, 4)
    }

    func testUploadFile_uploadRequestFails_throwsTypedError() async throws {
        let client = makeClient()
        let path = try makeTempFile(contents: "some file contents")

        MockURLProtocol.handler = { _ in
            .success(.init(statusCode: 500, data: Data("{}".utf8)))
        }

        do {
            _ = try await client.uploadFile(at: path, consentGiven: true)
            XCTFail("expected requestFailed to be thrown")
        } catch VirusTotalClientError.requestFailed(let statusCode, _) {
            XCTAssertEqual(statusCode, 500)
        } catch {
            XCTFail("expected .requestFailed, got \(error)")
        }
    }

    func testUploadFile_missingFile_throwsFileReadFailed() async {
        let client = makeClient()
        do {
            _ = try await client.uploadFile(at: "/nonexistent/path/does-not-exist.bin", consentGiven: true)
            XCTFail("expected fileReadFailed to be thrown")
        } catch VirusTotalClientError.fileReadFailed {
            // expected
        } catch {
            XCTFail("expected .fileReadFailed, got \(error)")
        }
        XCTAssertEqual(MockURLProtocol.recordedRequestCount, 0, "should fail before making any request")
    }

    // MARK: - helpers

    private func makeTempFile(contents: String) throws -> String {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data(contents.utf8).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url.path
    }
}
