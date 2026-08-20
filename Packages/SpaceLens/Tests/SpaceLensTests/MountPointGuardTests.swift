import XCTest
@testable import SpaceLens

/// Exercises `MountPointGuard`'s claim/reject state machine in isolation,
/// against synthetic device-id/container maps rather than a real second
/// mounted volume — fabricating an actual extra APFS volume or disk image
/// just for a unit test would be slow and machine-dependent, exactly what
/// the task calls for avoiding. The injectable `deviceIDProvider`/
/// `containerIDProvider` closures exist specifically to make this possible.
///
/// `testUnreadableDirectoryIsSkippedNotCrashing`-style end-to-end coverage
/// (does the dedup logic actually change what `DirectorySizeTreeBuilder`
/// counts) lives in `DirectorySizeTreeBuilderTests`.
final class MountPointGuardTests: XCTestCase {
    // MARK: - Same-device traffic is always fine

    func testPathsOnTheRootsOwnDeviceAreAlwaysAllowed() {
        let devices: [String: dev_t] = ["/root": 1, "/root/a": 1, "/root/a/b": 1]
        let guardObj = MountPointGuard(
            rootPath: "/root",
            deviceIDProvider: { devices[$0] },
            containerIDProvider: { _ in "container" }
        )

        XCTAssertTrue(guardObj.allowsDescending(into: "/root/a"))
        XCTAssertTrue(guardObj.allowsDescending(into: "/root/a/b"))
    }

    // MARK: - The one legitimate cross-volume case: the firmlinked Data volume

    func testFirstCrossingOntoTheRootsContainerIsClaimedAndAllowed() {
        // Simulates "/" (device 1) reaching the firmlinked Data volume
        // (device 2) via "/Users" — both share the same APFS container.
        let devices: [String: dev_t] = ["/": 1, "/Users": 2]
        let containers: [String: String] = ["/": "disk3", "/Users": "disk3"]
        let guardObj = MountPointGuard(
            rootPath: "/",
            deviceIDProvider: { devices[$0] },
            containerIDProvider: { containers[$0] }
        )

        XCTAssertTrue(guardObj.allowsDescending(into: "/Users"), "the Data volume's first path in should be walked")
    }

    func testASecondDifferentPathOntoAnAlreadyClaimedDeviceIsRejected() {
        // "/Users" and "/System/Volumes/Data" are two different paths that
        // both resolve onto the very same physical Data volume (device 2).
        // Walking both would double count every file reachable through
        // both — the second one in must be rejected.
        let devices: [String: dev_t] = ["/": 1, "/Users": 2, "/System/Volumes/Data": 2]
        let containers: [String: String] = [
            "/": "disk3", "/Users": "disk3", "/System/Volumes/Data": "disk3"
        ]
        let guardObj = MountPointGuard(
            rootPath: "/",
            deviceIDProvider: { devices[$0] },
            containerIDProvider: { containers[$0] }
        )

        XCTAssertTrue(guardObj.allowsDescending(into: "/Users"))
        XCTAssertFalse(
            guardObj.allowsDescending(into: "/System/Volumes/Data"),
            "same device already claimed via /Users — re-descending here would double count"
        )
    }

    func testDedupIsOrderIndependentWhicheverPathArrivesFirstWins() {
        // Same physical layout as above, but this time the walk happens to
        // reach "/System/Volumes/Data" before "/Users" (directory
        // enumeration order is never guaranteed) — the *first* one in must
        // win regardless of which path that happens to be.
        let devices: [String: dev_t] = ["/": 1, "/Users": 2, "/System/Volumes/Data": 2]
        let containers: [String: String] = [
            "/": "disk3", "/Users": "disk3", "/System/Volumes/Data": "disk3"
        ]
        let guardObj = MountPointGuard(
            rootPath: "/",
            deviceIDProvider: { devices[$0] },
            containerIDProvider: { containers[$0] }
        )

        XCTAssertTrue(guardObj.allowsDescending(into: "/System/Volumes/Data"))
        XCTAssertFalse(guardObj.allowsDescending(into: "/Users"))
    }

    // MARK: - Genuinely foreign volumes are excluded, not silently folded in

    func testAVolumeInADifferentContainerThanRootIsRejected() {
        // Simulates an external drive or network share mounted somewhere
        // under the tree (e.g. under "/Volumes") — a different disk
        // entirely, not part of the boot volume's own container.
        let devices: [String: dev_t] = ["/": 1, "/Volumes/Backup": 9]
        let containers: [String: String] = ["/": "disk3", "/Volumes/Backup": "disk7"]
        let guardObj = MountPointGuard(
            rootPath: "/",
            deviceIDProvider: { devices[$0] },
            containerIDProvider: { containers[$0] }
        )

        XCTAssertFalse(guardObj.allowsDescending(into: "/Volumes/Backup"))
    }

    func testRejectionOfAForeignVolumeIsCachedNotRecheckedPerPath() {
        var containerCheckCount = 0
        let devices: [String: dev_t] = ["/": 1, "/Volumes/Backup/a": 9, "/Volumes/Backup/b": 9]
        let containers: [String: String] = [
            "/": "disk3", "/Volumes/Backup/a": "disk7", "/Volumes/Backup/b": "disk7"
        ]
        let guardObj = MountPointGuard(
            rootPath: "/",
            deviceIDProvider: { devices[$0] },
            containerIDProvider: { path in
                containerCheckCount += 1
                return containers[path]
            }
        )

        XCTAssertFalse(guardObj.allowsDescending(into: "/Volumes/Backup/a"))
        XCTAssertFalse(guardObj.allowsDescending(into: "/Volumes/Backup/b"))
        // One container check happens in `init` for the root path itself,
        // plus exactly one for the shared foreign device's first sighting —
        // the second path onto that same device must short-circuit on the
        // cached rejection rather than repeating the (relatively expensive)
        // statfs-backed container check.
        XCTAssertEqual(containerCheckCount, 2)
    }

    // MARK: - Can't stat it: defer, don't guess

    func testAnUnstattablePathIsAllowedThroughToNormalErrorHandling() {
        // `MountPointGuard` isn't responsible for permission/vanished-file
        // handling — that's `node(at:...)`'s job further down. If it can't
        // even get a device id for a path, it shouldn't be the one to
        // decide the path is out of scope.
        let guardObj = MountPointGuard(
            rootPath: "/root",
            deviceIDProvider: { _ in nil },
            containerIDProvider: { _ in nil }
        )
        XCTAssertTrue(guardObj.allowsDescending(into: "/root/vanished"))
    }

    // MARK: - Real filesystem sanity (fast — no full-volume walk)

    func testRealDeviceIDIsObtainableForKnownExistingPaths() {
        // Every real Mac can lstat its own root and its own temp directory;
        // this is a cheap, fast, non-hanging smoke test that the raw
        // `lstat`-based helper actually works against the real filesystem,
        // as opposed to only ever being exercised through injected fakes.
        XCTAssertNotNil(deviceID(of: "/"))
        XCTAssertNotNil(deviceID(of: NSTemporaryDirectory()))
    }

    func testRealContainerIdentifierLooksLikeALocalDiskName() throws {
        let container = try XCTUnwrap(
            containerIdentifier(of: "/"),
            "statfs(\"/\") should always resolve to a local BSD disk device on a real Mac"
        )
        XCTAssertTrue(
            container.range(of: #"^disk[0-9]+$"#, options: .regularExpression) != nil,
            "expected something like \"disk3\", got \(container)"
        )
    }

    func testUnknownPathReturnsNilDeviceIDRatherThanCrashing() {
        XCTAssertNil(deviceID(of: "/this/path/almost-certainly-does-not-exist-\(UUID().uuidString)"))
        XCTAssertNil(containerIdentifier(of: "/this/path/almost-certainly-does-not-exist-\(UUID().uuidString)"))
    }
}
