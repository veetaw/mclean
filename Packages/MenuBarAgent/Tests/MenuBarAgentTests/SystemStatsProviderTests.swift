import XCTest
@testable import MenuBarAgent

/// Light smoke tests against the real low-level implementation. These are
/// intentionally not asserting specific values (CPU load, memory pressure,
/// and battery presence are all nondeterministic/machine-dependent) -- they
/// exist to catch "the syscall bridging is wrong and it crashes / always
/// reports unavailable" regressions, not to pin exact numbers.
final class SystemStatsProviderTests: XCTestCase {
    func testSnapshotDoesNotCrashAndDiskSpaceIsReadable() async {
        let provider = SystemStatsProvider()
        let first = await provider.snapshot()

        XCTAssertNotNil(first.diskSpace.value, "statfs on the home directory should succeed on any real macOS test runner")
        if let disk = first.diskSpace.value {
            XCTAssertGreaterThan(disk.totalBytes, 0)
        }
    }

    func testFirstCPUSampleIsUnavailableAndSecondHasAPlausibleDelta() async {
        let provider = SystemStatsProvider()
        let first = await provider.snapshot()
        XCTAssertNil(first.cpuUsageFraction.value, "no delta exists yet on the very first sample")

        let second = await provider.snapshot()
        if let cpu = second.cpuUsageFraction.value {
            XCTAssertGreaterThanOrEqual(cpu, 0)
            XCTAssertLessThanOrEqual(cpu, 1)
        }
    }

    func testMemorySnapshotIsPlausibleWhenAvailable() async {
        let provider = SystemStatsProvider()
        let snapshot = await provider.snapshot()
        if let memory = snapshot.memory.value {
            XCTAssertGreaterThan(memory.totalBytes, 0)
            XCTAssertGreaterThanOrEqual(memory.usedBytes, 0)
        }
    }

    func testDiskSpaceGracefullyDegradesForANonexistentPath() async {
        let provider = SystemStatsProvider(diskPath: "/this/path/does/not/exist/at/all")
        let snapshot = await provider.snapshot()
        XCTAssertNil(snapshot.diskSpace.value)
    }
}
