import CoreScanEngine
import Foundation
import SafetyRules
import XCTest
@testable import MenuBarAgent

// MARK: - Clock

/// Test-only mutable clock. `@unchecked Sendable` is justified here (and
/// only here, in test-only code): every read and write goes through `lock`,
/// which gives genuine thread-safety that the compiler simply can't verify
/// through a plain class with a `var`.
final class TestClock: Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ date: Date) {
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

/// Test-only `Sleeping` that suspends on a continuation the test controls
/// directly, instead of waiting on real time. `sleep(for:)` either resumes
/// immediately (if `release()` was already called with nothing waiting) or
/// parks until the test calls `release()`.
actor GatedSleeper: Sleeping {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var pendingReleases = 0

    var waitingCount: Int { waiters.count }

    func sleep(for seconds: TimeInterval) async {
        if pendingReleases > 0 {
            pendingReleases -= 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    /// Resumes the oldest currently-parked `sleep` call (FIFO), or -- if
    /// none is parked yet -- arranges for the *next* `sleep` call to return
    /// immediately.
    func release() {
        if waiters.isEmpty {
            pendingReleases += 1
        } else {
            waiters.removeFirst().resume()
        }
    }
}

/// Polls `condition` via cooperative `Task.yield()`s (no real timer/sleep
/// involved) until it becomes true or the iteration budget runs out --
/// bridges "the actor hasn't scheduled its inner Task yet" gaps in async
/// tests deterministically without depending on wall-clock time.
func pollUntil(
    maxIterations: Int = 100_000,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ condition: () async -> Bool
) async {
    for _ in 0..<maxIterations {
        if await condition() { return }
        await Task.yield()
    }
    XCTFail("condition not satisfied before iteration budget was exhausted", file: file, line: line)
}

/// Yields cooperatively `times` times with no assertion -- used to give
/// other pending tasks a fair chance to run before checking a final state,
/// without depending on wall-clock time or ever failing the test itself.
func yieldMany(_ times: Int = 200) async {
    for _ in 0..<times {
        await Task.yield()
    }
}

// MARK: - Notifications

actor RecordingNotificationPoster: NotificationPosting {
    private(set) var posts: [(identifier: String, title: String, body: String)] = []

    func post(identifier: String, title: String, body: String) async {
        posts.append((identifier, title, body))
    }
}

// MARK: - Disk space

/// Test-only mutable disk space double. `@unchecked Sendable` justified as
/// with `TestClock`: all access is serialized through `lock`.
final class MutableDiskSpaceProvider: DiskSpaceProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var free: Int64
    private var total: Int64

    init(free: Int64, total: Int64) {
        self.free = free
        self.total = total
    }

    func setFree(_ free: Int64) {
        lock.lock()
        defer { lock.unlock() }
        self.free = free
    }

    func freeAndTotalBytes(atPath path: String) throws -> (free: Int64, total: Int64) {
        lock.lock()
        defer { lock.unlock() }
        return (free, total)
    }
}

// MARK: - Quarantine

enum FakeQuarantineError: Error {
    case notImplemented
}

/// Fixture-only `QuarantineManaging`: never touches real paths, per the
/// checkpoint note on `QuarantineManaging` itself. Only `listActive()` is
/// exercised by `QuarantineSummaryReader`; the mutating methods aren't
/// needed by any `MenuBarAgent` code path, so they simply throw if ever
/// called.
struct FakeQuarantineManaging: QuarantineManaging {
    let receipts: [QuarantineReceipt]

    func quarantine(_ item: ScanItem, retention: QuarantinePolicy) async throws -> QuarantineReceipt {
        throw FakeQuarantineError.notImplemented
    }

    func restore(_ receipt: QuarantineReceipt) async throws {
        throw FakeQuarantineError.notImplemented
    }

    func purgeExpired() async throws -> [QuarantineReceipt] {
        throw FakeQuarantineError.notImplemented
    }

    func listActive() async throws -> [QuarantineReceipt] {
        receipts
    }
}

// MARK: - Misc

actor FireCounter {
    private(set) var count = 0

    func increment() {
        count += 1
    }
}
