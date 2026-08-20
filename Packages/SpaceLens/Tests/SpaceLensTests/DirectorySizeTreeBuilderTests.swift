import XCTest
@testable import SpaceLens

final class DirectorySizeTreeBuilderTests: XCTestCase {
    var home: String!
    let fm = FileManager.default

    override func setUp() {
        super.setUp()
        home = TempHome.make()
    }

    override func tearDown() {
        TempHome.cleanup(home)
        home = nil
        super.tearDown()
    }

    private func build(
        maxDepth: Int = 10,
        maxChildrenPerDirectory: Int = 1000,
        maxNodesBudget: Int = 100_000,
        isCancelled: @escaping @Sendable () -> Bool = { false }
    ) -> DirectoryNode? {
        DirectorySizeTreeBuilder.build(
            root: URL(fileURLWithPath: home),
            maxDepth: maxDepth,
            maxChildrenPerDirectory: maxChildrenPerDirectory,
            maxNodesBudget: maxNodesBudget,
            isCancelled: isCancelled
        )
    }

    // MARK: - Bottom-up size aggregation

    func testBottomUpSizeAggregationAcrossNestedDirectories() throws {
        fm.makeFile(home + "/root-file.bin", sizeBytes: 300)
        fm.makeFile(home + "/a/file1.bin", sizeBytes: 1000)
        fm.makeFile(home + "/a/file2.bin", sizeBytes: 2000)
        fm.makeFile(home + "/b/file3.bin", sizeBytes: 500)

        let root = try XCTUnwrap(build())

        XCTAssertEqual(root.sizeBytes, 3800)
        XCTAssertEqual(root.kind, .directory)

        let a = try XCTUnwrap(root.children.first { $0.name == "a" })
        XCTAssertEqual(a.sizeBytes, 3000)
        XCTAssertEqual(a.kind, .directory)

        let b = try XCTUnwrap(root.children.first { $0.name == "b" })
        XCTAssertEqual(b.sizeBytes, 500)

        let rootFile = try XCTUnwrap(root.children.first { $0.name == "root-file.bin" })
        XCTAssertEqual(rootFile.sizeBytes, 300)
        XCTAssertEqual(rootFile.kind, .file)
        XCTAssertTrue(rootFile.children.isEmpty)
    }

    func testFileNodeSizeMatchesActualFileSize() throws {
        fm.makeFile(home + "/solo.bin", sizeBytes: 4096)

        let root = try XCTUnwrap(build())
        let solo = try XCTUnwrap(root.children.first)

        XCTAssertEqual(solo.kind, .file)
        XCTAssertEqual(solo.sizeBytes, 4096)
    }

    func testEmptyDirectoryHasZeroSizeAndNoChildren() throws {
        fm.makeDir(home + "/empty")

        let root = try XCTUnwrap(build())
        let empty = try XCTUnwrap(root.children.first { $0.name == "empty" })

        XCTAssertEqual(empty.sizeBytes, 0)
        XCTAssertTrue(empty.children.isEmpty)
        XCTAssertEqual(empty.kind, .directory)
    }

    func testDeeplyNestedSizesSumCorrectlyToTheRoot() throws {
        fm.makeFile(home + "/x/y/z/deep.bin", sizeBytes: 123)
        fm.makeFile(home + "/x/shallow.bin", sizeBytes: 7)

        let root = try XCTUnwrap(build())
        XCTAssertEqual(root.sizeBytes, 130)

        let x = try XCTUnwrap(root.children.first { $0.name == "x" })
        XCTAssertEqual(x.sizeBytes, 130)

        let y = try XCTUnwrap(x.children.first { $0.name == "y" })
        XCTAssertEqual(y.sizeBytes, 123)

        let z = try XCTUnwrap(y.children.first { $0.name == "z" })
        XCTAssertEqual(z.sizeBytes, 123)

        let deep = try XCTUnwrap(z.children.first { $0.name == "deep.bin" })
        XCTAssertEqual(deep.sizeBytes, 123)
    }

    // MARK: - Depth limit

    func testMaxDepthStopsMaterializingChildrenButKeepsAccurateSize() throws {
        // depth 0 = home, 1 = l1, 2 = l2, 3 = l3 (file lives here)
        fm.makeFile(home + "/l1/l2/l3/deepfile.bin", sizeBytes: 777)

        // maxDepth = 1: root (depth 0) materializes children; l1 (depth 1)
        // is reached at depth == maxDepth, so it becomes a leaf — no
        // children materialized for it — but its size must still be exact.
        let root = try XCTUnwrap(build(maxDepth: 1))
        let l1 = try XCTUnwrap(root.children.first { $0.name == "l1" })

        XCTAssertTrue(l1.children.isEmpty, "l1 hit the depth ceiling and should not have materialized children")
        XCTAssertEqual(l1.sizeBytes, 777, "size must still be accurate even though children weren't broken out")
        XCTAssertEqual(root.sizeBytes, 777)
    }

    func testMaxDepthOneLevelDeeperStillMaterializesThatLevel() throws {
        fm.makeFile(home + "/l1/l2/l3/deepfile.bin", sizeBytes: 777)

        // maxDepth = 2: l1 (depth 1) still gets children materialized
        // (1 < 2); l2 (depth 2) hits the ceiling and becomes a leaf.
        let root = try XCTUnwrap(build(maxDepth: 2))
        let l1 = try XCTUnwrap(root.children.first { $0.name == "l1" })
        XCTAssertFalse(l1.children.isEmpty)

        let l2 = try XCTUnwrap(l1.children.first { $0.name == "l2" })
        XCTAssertTrue(l2.children.isEmpty)
        XCTAssertEqual(l2.sizeBytes, 777)
    }

    // MARK: - Per-directory child cap / aggregation

    func testMaxChildrenPerDirectoryCapsNodeCountAndAddsAggregate() throws {
        for i in 0..<10 {
            fm.makeFile(home + "/many/file\(i).bin", sizeBytes: (i + 1) * 100)
        }
        // Total = 100+200+...+1000 = 5500

        let root = try XCTUnwrap(build(maxChildrenPerDirectory: 5))
        let many = try XCTUnwrap(root.children.first { $0.name == "many" })

        XCTAssertEqual(many.children.count, 5, "4 largest kept individually + 1 aggregate")
        XCTAssertEqual(many.sizeBytes, 5500, "total size must be preserved even when entries are folded into an aggregate")

        let aggregate = try XCTUnwrap(many.children.first { $0.kind == .aggregate })
        XCTAssertEqual(aggregate.children.count, 0)

        // The 4 largest individual files are file9 (1000) down to file6 (700);
        // the aggregate folds the remaining 6 (100+200+300+400+500+600 = 2100).
        XCTAssertEqual(aggregate.sizeBytes, 2100)

        let individualNames = Set(many.children.filter { $0.kind == .file }.map(\.name))
        XCTAssertEqual(individualNames, ["file9.bin", "file8.bin", "file7.bin", "file6.bin"])
    }

    func testChildrenAtOrBelowTheCapAreNotAggregated() throws {
        for i in 0..<5 {
            fm.makeFile(home + "/few/file\(i).bin", sizeBytes: 100)
        }

        let root = try XCTUnwrap(build(maxChildrenPerDirectory: 5))
        let few = try XCTUnwrap(root.children.first { $0.name == "few" })

        XCTAssertEqual(few.children.count, 5)
        XCTAssertFalse(few.children.contains { $0.kind == .aggregate })
    }

    // MARK: - Global node budget

    func testMaxNodesBudgetBoundsTotalWorkWithoutCrashing() throws {
        for i in 0..<200 {
            fm.makeFile(home + "/budget/file\(i).bin", sizeBytes: 10)
        }

        // A tiny budget: the root itself + "budget" dir already consumes 2,
        // leaving very little room — the walk must still terminate cleanly
        // (never crash/hang) rather than blowing past the budget on *full*
        // (recursively-subdividing) node materialization.
        //
        // It's no longer true that the whole tree's node count stays
        // <= the budget, though: once the budget runs out, remaining
        // siblings fall back to cheap, budget-exempt, non-subdividing
        // leaves (see `DirectorySizeTreeBuilder`'s type doc comment) so
        // `root`'s reported total size stays accurate instead of silently
        // undercounting — that fallback adds one flat leaf node per
        // remaining sibling (bounded by how many entries the directory
        // that was being enumerated when the budget ran out actually has;
        // never recursive, so this can't cascade or hang), which is
        // exactly what's checked below alongside the accurate total.
        let root = try XCTUnwrap(build(maxChildrenPerDirectory: 1000, maxNodesBudget: 10))

        func countNodes(_ node: DirectoryNode) -> Int {
            1 + node.children.reduce(0) { $0 + countNodes($1) }
        }

        // root + "budget" already spend 2 of the 10-node budget; the
        // remaining ~198 files under "budget" all fall back to flat,
        // budget-exempt leaves once the budget hits zero, so the total
        // node count is bounded by (budget) + (however many siblings were
        // still left in whatever directory was being enumerated at that
        // moment) — not unbounded, but also not <= budget any more.
        XCTAssertEqual(countNodes(root), 202, "2 real nodes (root, \"budget\") + 200 budget-exempt flat file leaves")
        XCTAssertEqual(root.sizeBytes, 2000, "size must stay exact even though the budget ran out — this is the whole point of the fallback")
    }

    // MARK: - Cancellation

    func testCancellationBeforeStartReturnsNil() throws {
        fm.makeFile(home + "/file.bin", sizeBytes: 10)

        let result = build(isCancelled: { true })
        XCTAssertNil(result)
    }

    func testCancellationMidWalkTerminatesPromptly() throws {
        for i in 0..<500 {
            fm.makeFile(home + "/lots/file\(i).bin", sizeBytes: 10)
        }

        final class Counter: @unchecked Sendable {
            private let lock = NSLock()
            private var value = 0
            func incrementAndCheck(threshold: Int) -> Bool {
                lock.lock()
                defer { lock.unlock() }
                value += 1
                return value > threshold
            }
        }
        let counter = Counter()

        let start = Date()
        // Cancels after a handful of node visits — the walk must return
        // quickly rather than continuing to materialize all 500 files.
        let result = build(maxChildrenPerDirectory: 1000, isCancelled: { counter.incrementAndCheck(threshold: 5) })
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(elapsed, 5.0, "cancellation should stop the walk promptly")
        if let result {
            func countNodes(_ node: DirectoryNode) -> Int {
                1 + node.children.reduce(0) { $0 + countNodes($1) }
            }
            XCTAssertLessThan(countNodes(result), 500, "cancellation should have cut the walk short")
        }
    }

    // MARK: - Symlinks

    func testSymlinksAreNeverFollowed() throws {
        fm.makeFile(home + "/real/target.bin", sizeBytes: 999)
        fm.makeSymlink(at: home + "/link-to-real", to: home + "/real")

        let root = try XCTUnwrap(build())

        XCTAssertFalse(root.children.contains { $0.name == "link-to-real" })
        // Total size must only reflect the real file once, not the symlink.
        XCTAssertEqual(root.sizeBytes, 999)
    }

    // MARK: - Permission errors

    func testUnreadableDirectoryIsSkippedNotCrashing() throws {
        fm.makeFile(home + "/visible/ok.bin", sizeBytes: 50)
        fm.makeFile(home + "/locked/secret.bin", sizeBytes: 999)
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: home + "/locked")
        defer { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: home + "/locked") }

        // Must not throw/crash regardless of whether the current process
        // (e.g. root in some CI environments) actually gets denied.
        let root = try XCTUnwrap(build())
        XCTAssertTrue(root.children.contains { $0.name == "visible" })
    }

    /// Simulates the same shape of permission wall a real "/" scan hits at
    /// scale (many small SIP-protected directories, not just one) and
    /// confirms it degrades gracefully rather than slowing down
    /// pathologically or dropping unrelated siblings.
    func testManyUnreadableDirectoriesAmongReadableOnesStayFastAndAccurate() throws {
        for i in 0..<200 {
            fm.makeDir(home + "/locked\(i)")
            try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: home + "/locked\(i)")
        }
        defer {
            for i in 0..<200 {
                try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: home + "/locked\(i)")
            }
        }
        fm.makeFile(home + "/visible/ok.bin", sizeBytes: 321)

        let start = Date()
        let root = try XCTUnwrap(build(maxChildrenPerDirectory: 1000))
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(elapsed, 5.0, "200 unreadable directories must resolve near-instantly, not hang")
        let visible = try XCTUnwrap(root.children.first { $0.name == "visible" })
        XCTAssertEqual(visible.sizeBytes, 321, "an unreadable sibling must never corrupt an unrelated readable directory's size")
    }

    // MARK: - Mount-point deduplication (end-to-end, via the injectable `MountPointGuard`)

    /// Builds `root` with a synthetic `MountPointGuard` standing in for a
    /// real second mounted volume, so this test exercises the *actual*
    /// `DirectorySizeTreeBuilder` walk deciding what to count — not just
    /// `MountPointGuard`'s isolated state machine (see `MountPointGuardTests`).
    private func buildWithVolumeGuard(
        deviceIDProvider: @escaping (String) -> dev_t?,
        containerIDProvider: @escaping (String) -> String?
    ) -> DirectoryNode? {
        DirectorySizeTreeBuilder.build(
            root: URL(fileURLWithPath: home),
            maxChildrenPerDirectory: 1000,
            volumeGuard: MountPointGuard(
                rootPath: home,
                deviceIDProvider: deviceIDProvider,
                containerIDProvider: containerIDProvider
            )
        )
    }

    func testTwoPathsResolvingToTheSameDeviceAreCountedOnlyOnce() throws {
        // "dataFirst" and "dataSecond" are two different real directories in
        // this temp fixture, but the injected device map tells the guard
        // they're actually the *same* physical volume (device 2) — the
        // same situation "/Users" and "/System/Volumes/Data" are really in
        // on a real Mac. Only whichever one the walk reaches first should
        // be counted; the second must contribute nothing.
        fm.makeFile(home + "/onRootDevice/plain.bin", sizeBytes: 111)
        fm.makeFile(home + "/dataFirst/inside.bin", sizeBytes: 7000)
        fm.makeFile(home + "/dataSecond/inside2.bin", sizeBytes: 9000)

        // Matched by suffix, not exact equality: `FileManager.contentsOfDirectory`
        // returns fully-resolved paths (e.g. under `/private/var/...` even
        // though `home` itself was built from the unresolved
        // `NSTemporaryDirectory()`, which is `/var/...` on a real Mac), so
        // comparing the raw `home + "/dataFirst"` string against what the
        // walk actually sees would silently never match.
        let root = try XCTUnwrap(buildWithVolumeGuard(
            deviceIDProvider: { path in
                if path.hasSuffix("/dataFirst") || path.hasSuffix("/dataSecond") { return 2 }
                return 1 // root's own device for everything else, including `home` itself
            },
            containerIDProvider: { _ in "sharedContainer" } // same APFS container for everyone
        ))

        let dataFirst = try XCTUnwrap(root.children.first { $0.name == "dataFirst" })
        let dataSecond = try XCTUnwrap(root.children.first { $0.name == "dataSecond" })
        let onRootDevice = try XCTUnwrap(root.children.first { $0.name == "onRootDevice" })

        // Exactly one of the two duplicate-volume directories was walked
        // (whichever the (unordered) directory listing happened to reach
        // first) and the other reports zero — never both, which would mean
        // double counting, and never neither, which would mean the volume
        // was dropped entirely.
        let walkedCount = [dataFirst.sizeBytes, dataSecond.sizeBytes].filter { $0 > 0 }.count
        XCTAssertEqual(walkedCount, 1, "exactly one duplicate path onto the shared device should be walked")
        XCTAssertTrue(
            (dataFirst.sizeBytes == 7000 && dataSecond.sizeBytes == 0)
                || (dataFirst.sizeBytes == 0 && dataSecond.sizeBytes == 9000),
            "whichever path lost the race must be exactly zero, not partially counted"
        )

        XCTAssertEqual(onRootDevice.sizeBytes, 111, "ordinary same-device directories are unaffected")
        XCTAssertEqual(
            root.sizeBytes,
            111 + dataFirst.sizeBytes + dataSecond.sizeBytes,
            "root's total must equal exactly what was actually walked — no hidden double count"
        )
        XCTAssertLessThan(root.sizeBytes, 111 + 7000 + 9000, "double counting both duplicate paths must never happen")
    }

    func testAVolumeInADifferentContainerIsExcludedEntirely() throws {
        // Simulates an unrelated external/network volume mounted somewhere
        // under the tree — must contribute nothing to the total, but the
        // directory itself still appears (as an empty leaf) rather than
        // vanishing from its parent's listing.
        fm.makeFile(home + "/local/keep.bin", sizeBytes: 55)
        fm.makeFile(home + "/externalDrive/bigfile.bin", sizeBytes: 50_000)

        // Suffix match, not exact equality — see the comment in
        // `testTwoPathsResolvingToTheSameDeviceAreCountedOnlyOnce` above for
        // why (`contentsOfDirectory` returns fully-resolved paths).
        let root = try XCTUnwrap(buildWithVolumeGuard(
            deviceIDProvider: { path in path.hasSuffix("/externalDrive") ? 9 : 1 },
            containerIDProvider: { path in path.hasSuffix("/externalDrive") ? "otherDisk" : "rootDisk" }
        ))

        let external = try XCTUnwrap(root.children.first { $0.name == "externalDrive" })
        XCTAssertEqual(external.sizeBytes, 0, "a foreign volume must never contribute to the reported total")
        XCTAssertTrue(external.children.isEmpty)

        let local = try XCTUnwrap(root.children.first { $0.name == "local" })
        XCTAssertEqual(local.sizeBytes, 55)
        XCTAssertEqual(root.sizeBytes, 55, "the foreign volume's 50,000 bytes must be excluded from the boot-volume total")
    }

    // MARK: - Budget-exhaustion graceful degradation

    func testBudgetExhaustionKeepsSiblingsAccuratelySizedInsteadOfOmittingThem() throws {
        // "first" alone (50 small files) is sized to blow well past a tiny
        // budget; "second" has one file. Directory-listing order for
        // `home`'s two top-level entries is unspecified, so this can't
        // assume which one the walk reaches with budget still available —
        // it only asserts that *both* still show up with their real,
        // accurate total size, which is the property that matters once the
        // root is an entire disk rather than one home directory.
        for i in 0..<50 {
            fm.makeFile(home + "/first/file\(i).bin", sizeBytes: 10)
        }
        fm.makeFile(home + "/second/onlyfile.bin", sizeBytes: 4242)

        let root = try XCTUnwrap(build(maxChildrenPerDirectory: 1000, maxNodesBudget: 5))

        XCTAssertEqual(root.children.count, 2, "both top-level directories must still appear despite the tiny budget")

        let first = try XCTUnwrap(root.children.first { $0.name == "first" })
        let second = try XCTUnwrap(root.children.first { $0.name == "second" })

        XCTAssertEqual(first.sizeBytes, 500, "\"first\"'s total must be accurate even if its own children weren't individually materialized")
        XCTAssertEqual(second.sizeBytes, 4242, "\"second\" must not be silently dropped/undercounted just because the budget ran out before reaching it")
        XCTAssertEqual(root.sizeBytes, 500 + 4242)
    }
}
