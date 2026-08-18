import XCTest
import CoreScanEngine
@testable import DevToolsDetectors

final class PythonDetectorTests: XCTestCase {
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

    func testFindsPipCache() async throws {
        fm.makeFile(home + "/Library/Caches/pip/wheels/foo.whl")

        let items = try await PythonDetector().scan(context: scanContext(roots: [home]))

        let pip = items.first { $0.sourceDetectorID == "dev.python.pip-cache" }
        XCTAssertNotNil(pip)
        XCTAssertEqual(pip?.path, home + "/Library/Caches/pip")
        XCTAssertNotNil(pip?.sizeBytes)
        XCTAssertGreaterThan(pip?.sizeBytes ?? 0, 0)
    }

    func testFindsCondaPackageCache() async throws {
        fm.makeFile(home + "/.conda/pkgs/numpy-1.0/info/index.json")

        let items = try await PythonDetector().scan(context: scanContext(roots: [home]))

        XCTAssertTrue(items.contains { $0.sourceDetectorID == "dev.python.conda-pkgs-cache" })
    }

    func testFindsJupyterCache() async throws {
        fm.makeFile(home + "/.cache/jupyter/runtime/kernel.json")
        fm.makeFile(home + "/.local/share/jupyter/kernels/python3/kernel.json")

        let items = try await PythonDetector().scan(context: scanContext(roots: [home]))

        let jupyterPaths = Set(items.filter { $0.sourceDetectorID == "dev.python.jupyter-cache" }.map(\.path))
        XCTAssertEqual(jupyterPaths, [home + "/.cache/jupyter", home + "/.local/share/jupyter"])
    }

    func testFindsStrayPycacheDirectories() async throws {
        fm.makeFile(home + "/projects/myapp/__pycache__/module.cpython-311.pyc")
        fm.makeFile(home + "/Library/SomeUnrelatedThing/__pycache__/x.pyc") // under Library, should be skipped

        let items = try await PythonDetector().scan(context: scanContext(roots: [home]))

        let pycachePaths = items.filter { $0.sourceDetectorID == "dev.python.pycache" }.map(\.path)
        XCTAssertEqual(pycachePaths, [home + "/projects/myapp/__pycache__"])
    }

    func testOrphanedVirtualenvIsFlaggedWhenProjectMarkerMissingTarget() async throws {
        let venv = home + "/.local/share/virtualenvs/myproj-abc123"
        fm.makeFile(venv + "/pyvenv.cfg", contents: "home = /usr/bin\n")
        fm.makeFile(venv + "/.project", contents: home + "/projects/myproj-does-not-exist")

        let items = try await PythonDetector().scan(context: scanContext(roots: [home]))

        let orphan = items.first { $0.sourceDetectorID == "dev.python.orphaned-virtualenv" }
        XCTAssertNotNil(orphan)
        XCTAssertEqual(orphan?.path, venv)
        XCTAssertTrue(orphan?.reason.contains("no longer exists") ?? false)
    }

    func testVirtualenvNotFlaggedWhenProjectMarkerStillExists() async throws {
        let project = home + "/projects/myproj"
        fm.makeDir(project)
        let venv = home + "/.local/share/virtualenvs/myproj-abc123"
        fm.makeFile(venv + "/pyvenv.cfg", contents: "home = /usr/bin\n")
        fm.makeFile(venv + "/.project", contents: project)

        let items = try await PythonDetector().scan(context: scanContext(roots: [home]))

        XCTAssertFalse(items.contains { $0.path == venv })
    }

    func testVirtualenvWithoutProjectMarkerIsBestEffortCandidateWhenStale() async throws {
        let venv = home + "/.virtualenvs/legacy-env"
        fm.makeFile(venv + "/pyvenv.cfg", contents: "home = /usr/bin\n")
        fm.setModificationDate(daysAgo(400), at: venv)

        let detector = PythonDetector(staleVirtualenvThreshold: 180 * 24 * 3600, now: { testReferenceDate })
        let items = try await detector.scan(context: scanContext(roots: [home]))

        let candidate = items.first { $0.sourceDetectorID == "dev.python.stale-virtualenv-candidate" }
        XCTAssertNotNil(candidate)
        XCTAssertTrue(candidate?.reason.contains("Best-effort") ?? false)
    }

    func testRespectsCancellation() async throws {
        fm.makeFile(home + "/Library/Caches/pip/wheels/foo.whl")
        let root = home!

        let task = Task { () -> [ScanItem] in
            try await PythonDetector().scan(context: ScanContext(roots: [root]))
        }
        task.cancel()
        // Should complete without throwing/hanging even when cancelled
        // immediately; content isn't asserted since cancellation may race
        // with the (very fast) scan on a small tree.
        _ = try await task.value
    }
}
