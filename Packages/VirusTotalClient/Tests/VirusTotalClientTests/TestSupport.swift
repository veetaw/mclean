import Foundation
@testable import VirusTotalClient

// MARK: - Clock

/// Test-only mutable clock. `@unchecked Sendable` is justified here (and
/// only here, in test-only code): every read and write goes through `lock`,
/// which gives genuine thread-safety the compiler can't verify through a
/// plain class with a `var`. Mirrors `MenuBarAgentTests.TestClock`.
final class TestClock: Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ date: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        current = date
    }

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func advance(by interval: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        current = current.addingTimeInterval(interval)
    }
}

// MARK: - Sleeping

/// Test-only `Sleeping` that never actually waits: it records the requested
/// duration and immediately advances a paired `TestClock` by that amount,
/// simulating time passing without a test ever blocking on real time.
final actor FakeSleeper: Sleeping {
    private let clock: TestClock
    private(set) var sleepCalls: [TimeInterval] = []

    init(clock: TestClock) {
        self.clock = clock
    }

    func sleep(for seconds: TimeInterval) async {
        sleepCalls.append(seconds)
        clock.advance(by: seconds)
    }
}

// MARK: - Locked counter

/// Thread-safe mutable counter for test closures (e.g. `MockURLProtocol`
/// handlers) that run off the main actor and need to count invocations
/// without tripping strict-concurrency captured-var checks.
final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    @discardableResult
    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return count
    }
}

// MARK: - URLProtocol network mock

/// Intercepts every request made through a `URLSession` configured with it
/// in `protocolClasses`, so tests never make real network calls. Register a
/// `handler` (via `makeMockedSession`) that maps a request to a canned
/// status/body, or to a transport error.
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    struct Stub {
        let statusCode: Int
        let data: Data
        let headers: [String: String]

        init(statusCode: Int, data: Data, headers: [String: String] = [:]) {
            self.statusCode = statusCode
            self.data = data
            self.headers = headers
        }
    }

    typealias Handler = @Sendable (URLRequest) -> Result<Stub, Error>

    private static let lock = NSLock()
    nonisolated(unsafe) private static var _handler: Handler?
    nonisolated(unsafe) private static var _recordedRequests: [URLRequest] = []

    static var handler: Handler? {
        get { lock.lock(); defer { lock.unlock() }; return _handler }
        set { lock.lock(); defer { lock.unlock() }; _handler = newValue }
    }

    static var recordedRequests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return _recordedRequests
    }

    static var recordedRequestCount: Int { recordedRequests.count }

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        _handler = nil
        _recordedRequests = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self._recordedRequests.append(request)
        let handler = Self._handler
        Self.lock.unlock()

        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }

        switch handler(request) {
        case .success(let stub):
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://www.virustotal.com")!,
                statusCode: stub.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: stub.headers
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: stub.data)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

/// Builds a `URLSession` that routes exclusively through `MockURLProtocol`
/// -- no real network access is possible through a session built this way.
func makeMockedSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}
