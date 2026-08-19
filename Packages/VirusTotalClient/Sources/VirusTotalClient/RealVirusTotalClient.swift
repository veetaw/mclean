import CryptoKit
import Foundation

/// Concrete `VirusTotalClient` conformer backed by real HTTP calls to the
/// VirusTotal v3 API (PROMPT MASTER §5.7).
///
/// - `lookupHash` — `GET /files/{sha256}`, header `x-apikey`. A 404 means
///   "VirusTotal has no record for this hash" and is mapped to `nil`, not an
///   error; any other non-2xx status throws `VirusTotalClientError
///   .requestFailed` so callers can tell "not found" apart from "actually
///   failed".
/// - `uploadFile` — refuses immediately (no network call at all, not even a
///   HEAD request) unless `consentGiven == true`. When consent is given, it
///   does a real multipart `POST /files`, then polls `GET
///   /analyses/{id}` a bounded number of times to try to get a completed
///   result. **What this does NOT do**: poll indefinitely. If the analysis
///   hasn't completed after `analysisPollAttempts` tries (default 5, one
///   VT-recommended interval apart), it gives up and returns a best-effort
///   report with zeroed stats and just the permalink, so the UI can show
///   "still scanning, check back" rather than hanging the call forever. A
///   fuller implementation could poll with unbounded backoff, or surface an
///   explicit "still pending" state distinct from "clean" to the caller
///   instead of folding it into zeroed stats — call sites should not treat
///   the zeroed-stats-plus-permalink case as equivalent to a real "harmless"
///   verdict from `lookupHash`.
///
/// Every real network call goes through the injected `VirusTotalRateLimiter`
/// first (`awaitSlot()`), so this type never fires a request while over
/// VirusTotal's public-tier budget. Nothing in this type loops over multiple
/// files/hashes on its own initiative — each call is for exactly one
/// file/hash, invoked by an explicit caller action.
public actor RealVirusTotalClient: VirusTotalClient {
    private let apiKey: String?
    private let session: URLSession
    private let rateLimiter: VirusTotalRateLimiter
    private let sleeper: Sleeping
    private let baseURL: URL
    private let analysisPollInterval: TimeInterval
    private let analysisPollAttempts: Int

    /// - Parameters:
    ///   - apiKey: The caller-supplied VirusTotal API key. `nil` or empty
    ///     means "not configured" — `isConfigured` will be `false` and both
    ///     `lookupHash`/`uploadFile` throw `.notConfigured` immediately.
    ///     Never hardcoded here.
    ///   - session: Injectable so tests can substitute a `URLSession`
    ///     configured with a mock `URLProtocol` and make zero real network
    ///     calls. Defaults to `.shared`.
    ///   - rateLimiter: Shared limiter every call goes through before
    ///     hitting the network.
    ///   - sleeper: Used only for the bounded wait between analysis polls in
    ///     `uploadFile`; injectable so tests never wait on real time.
    ///   - baseURL: VirusTotal's v3 API root. Overridable for tests, though
    ///     tests normally intercept at the `URLSession` layer instead.
    ///   - analysisPollInterval: Seconds between analysis polls after an
    ///     upload. VT recommends not polling faster than every ~15s.
    ///   - analysisPollAttempts: Maximum number of analysis polls before
    ///     giving up and returning a best-effort pending report.
    public init(
        apiKey: String?,
        session: URLSession = .shared,
        rateLimiter: VirusTotalRateLimiter = VirusTotalRateLimiter(),
        sleeper: Sleeping = TaskSleeper(),
        baseURL: URL = URL(string: "https://www.virustotal.com/api/v3")!,
        analysisPollInterval: TimeInterval = 15,
        analysisPollAttempts: Int = 5
    ) {
        self.apiKey = (apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
        self.session = session
        self.rateLimiter = rateLimiter
        self.sleeper = sleeper
        self.baseURL = baseURL
        self.analysisPollInterval = analysisPollInterval
        self.analysisPollAttempts = analysisPollAttempts
    }

    /// `nonisolated` because it only reads an immutable (`let`) stored
    /// property, which is safe without actor isolation — lets UI code check
    /// this synchronously without an `await`.
    public nonisolated var isConfigured: Bool {
        apiKey != nil
    }

    // MARK: - lookupHash

    public func lookupHash(_ sha256: String) async throws -> VirusTotalReport? {
        guard let apiKey else { throw VirusTotalClientError.notConfigured }

        let normalized = sha256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard Self.isValidSHA256(normalized) else {
            throw VirusTotalClientError.invalidHash(sha256)
        }

        try Task.checkCancellation()
        try await rateLimiter.awaitSlot()
        try Task.checkCancellation()

        var request = URLRequest(url: baseURL.appendingPathComponent("files").appendingPathComponent(normalized))
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "x-apikey")

        let (data, response) = try await session.data(for: request)
        let http = try Self.httpResponse(response)

        if http.statusCode == 404 {
            return nil
        }
        guard (200...299).contains(http.statusCode) else {
            throw VirusTotalClientError.requestFailed(statusCode: http.statusCode, message: Self.errorMessage(from: data))
        }

        return try Self.parseFileLookup(sha256: normalized, data: data)
    }

    // MARK: - uploadFile

    public func uploadFile(at path: String, consentGiven: Bool) async throws -> VirusTotalReport {
        // Checked first, before anything else — including reading the file
        // or touching the API key — so refusing consent never causes any
        // network activity, not even a HEAD request.
        guard consentGiven else {
            throw VirusTotalClientError.consentRequired
        }
        guard let apiKey else {
            throw VirusTotalClientError.notConfigured
        }

        let fileURL = URL(fileURLWithPath: path)
        let fileData: Data
        do {
            fileData = try Data(contentsOf: fileURL)
        } catch {
            throw VirusTotalClientError.fileReadFailed(error.localizedDescription)
        }
        let sha256 = Self.sha256Hex(of: fileData)

        try Task.checkCancellation()
        try await rateLimiter.awaitSlot()
        try Task.checkCancellation()

        let boundary = "MCleanPro-\(UUID().uuidString)"
        var request = URLRequest(url: baseURL.appendingPathComponent("files"))
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-apikey")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.multipartBody(filename: fileURL.lastPathComponent, fileData: fileData, boundary: boundary)

        let (data, response) = try await session.data(for: request)
        let http = try Self.httpResponse(response)
        guard (200...299).contains(http.statusCode) else {
            throw VirusTotalClientError.requestFailed(statusCode: http.statusCode, message: Self.errorMessage(from: data))
        }

        let analysisID = try Self.parseAnalysisID(data: data)
        return try await pollAnalysis(id: analysisID, sha256: sha256, apiKey: apiKey)
    }

    // MARK: - Analysis polling

    private func pollAnalysis(id: String, sha256: String, apiKey: String) async throws -> VirusTotalReport {
        var attempt = 0
        while attempt < analysisPollAttempts {
            try Task.checkCancellation()
            try await rateLimiter.awaitSlot()
            try Task.checkCancellation()

            var request = URLRequest(url: baseURL.appendingPathComponent("analyses").appendingPathComponent(id))
            request.httpMethod = "GET"
            request.setValue(apiKey, forHTTPHeaderField: "x-apikey")

            let (data, response) = try await session.data(for: request)
            let http = try Self.httpResponse(response)
            guard (200...299).contains(http.statusCode) else {
                throw VirusTotalClientError.requestFailed(statusCode: http.statusCode, message: Self.errorMessage(from: data))
            }

            if let report = try Self.parseCompletedAnalysis(sha256: sha256, data: data) {
                return report
            }

            attempt += 1
            if attempt < analysisPollAttempts {
                try Task.checkCancellation()
                await sleeper.sleep(for: analysisPollInterval)
            }
        }

        // Gave up waiting for completion — see the doc comment on
        // `uploadFile` for exactly what this return value does and doesn't
        // mean.
        return VirusTotalReport(
            sha256: sha256,
            maliciousCount: 0,
            suspiciousCount: 0,
            harmlessCount: 0,
            undetectedCount: 0,
            permalink: Self.guiPermalink(sha256: sha256)
        )
    }

    // MARK: - Parsing

    private static func httpResponse(_ response: URLResponse) throws -> HTTPURLResponse {
        guard let http = response as? HTTPURLResponse else {
            throw VirusTotalClientError.invalidResponse
        }
        return http
    }

    private struct FileLookupResponse: Decodable {
        struct DataObject: Decodable {
            struct Attributes: Decodable {
                struct Stats: Decodable {
                    let malicious: Int
                    let suspicious: Int
                    let harmless: Int
                    let undetected: Int
                }
                let last_analysis_stats: Stats
            }
            struct Links: Decodable {
                let itself: String?
                private enum CodingKeys: String, CodingKey {
                    case itself = "self"
                }
            }
            let attributes: Attributes
            let links: Links?
        }
        let data: DataObject
    }

    private static func parseFileLookup(sha256: String, data: Data) throws -> VirusTotalReport {
        let decoded: FileLookupResponse
        do {
            decoded = try JSONDecoder().decode(FileLookupResponse.self, from: data)
        } catch {
            throw VirusTotalClientError.decodingFailed(String(describing: error))
        }
        let stats = decoded.data.attributes.last_analysis_stats
        let permalink = decoded.data.links?.itself.flatMap(URL.init(string:)) ?? guiPermalink(sha256: sha256)
        return VirusTotalReport(
            sha256: sha256,
            maliciousCount: stats.malicious,
            suspiciousCount: stats.suspicious,
            harmlessCount: stats.harmless,
            undetectedCount: stats.undetected,
            permalink: permalink
        )
    }

    private struct UploadResponse: Decodable {
        struct DataObject: Decodable {
            let id: String
        }
        let data: DataObject
    }

    private static func parseAnalysisID(data: Data) throws -> String {
        do {
            return try JSONDecoder().decode(UploadResponse.self, from: data).data.id
        } catch {
            throw VirusTotalClientError.decodingFailed(String(describing: error))
        }
    }

    private struct AnalysisResponse: Decodable {
        struct DataObject: Decodable {
            struct Attributes: Decodable {
                struct Stats: Decodable {
                    let malicious: Int
                    let suspicious: Int
                    let harmless: Int
                    let undetected: Int
                }
                let status: String
                let stats: Stats?
            }
            let attributes: Attributes
        }
        let data: DataObject
    }

    /// Returns a report if the analysis has completed, `nil` if it's still
    /// queued/running (so the caller keeps polling).
    private static func parseCompletedAnalysis(sha256: String, data: Data) throws -> VirusTotalReport? {
        let decoded: AnalysisResponse
        do {
            decoded = try JSONDecoder().decode(AnalysisResponse.self, from: data)
        } catch {
            throw VirusTotalClientError.decodingFailed(String(describing: error))
        }
        let attributes = decoded.data.attributes
        guard attributes.status == "completed", let stats = attributes.stats else {
            return nil
        }
        return VirusTotalReport(
            sha256: sha256,
            maliciousCount: stats.malicious,
            suspiciousCount: stats.suspicious,
            harmlessCount: stats.harmless,
            undetectedCount: stats.undetected,
            permalink: guiPermalink(sha256: sha256)
        )
    }

    private struct ErrorEnvelope: Decodable {
        struct ErrorDetail: Decodable {
            let code: String?
            let message: String?
        }
        let error: ErrorDetail?
    }

    private static func errorMessage(from data: Data) -> String? {
        guard let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) else {
            return nil
        }
        if let code = envelope.error?.code, let message = envelope.error?.message {
            return "\(code): \(message)"
        }
        return envelope.error?.message ?? envelope.error?.code
    }

    private static func guiPermalink(sha256: String) -> URL? {
        URL(string: "https://www.virustotal.com/gui/file/\(sha256)")
    }

    // MARK: - Hashing / multipart

    private static func sha256Hex(of data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func multipartBody(filename: String, fileData: Data, boundary: String) -> Data {
        var body = Data()
        func append(_ string: String) {
            body.append(Data(string.utf8))
        }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: application/octet-stream\r\n\r\n")
        body.append(fileData)
        append("\r\n--\(boundary)--\r\n")
        return body
    }

    private static func isValidSHA256(_ candidate: String) -> Bool {
        candidate.count == 64 && candidate.allSatisfy(\.isHexDigit)
    }
}
