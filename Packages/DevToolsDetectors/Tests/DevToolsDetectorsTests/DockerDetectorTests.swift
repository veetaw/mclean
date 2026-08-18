import XCTest
import CoreScanEngine
@testable import DevToolsDetectors

/// Exercises `DockerDetector` without depending on Docker actually being
/// installed on the test machine: a tiny fake `docker` shell script is
/// placed on a sandboxed `PATH` so the detector's CLI-parsing logic is still
/// tested for real, and a separate test confirms the "not installed" path
/// degrades gracefully to an empty result instead of throwing or hanging.
final class DockerDetectorTests: XCTestCase {
    var binDir: String!
    let fm = FileManager.default

    override func setUp() {
        super.setUp()
        binDir = TempHome.make()
    }

    override func tearDown() {
        TempHome.cleanup(binDir)
        binDir = nil
        super.tearDown()
    }

    private func writeFakeDocker(script: String) {
        let path = binDir + "/docker"
        fm.makeFile(path, contents: script)
        try! fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
    }

    func testReturnsNoItemsWhenDockerIsNotOnPath() async throws {
        let detector = DockerDetector(environment: ["PATH": "/nonexistent-bin-dir-for-tests"])
        let items = try await detector.scan(context: scanContext(roots: [TempHome.make()]))
        XCTAssertTrue(items.isEmpty)
    }

    func testParsesDanglingImagesVolumesAndBuildCacheFromFakeDockerCLI() async throws {
        writeFakeDocker(script: """
        #!/bin/sh
        case "$1" in
          --version) echo "Docker version 24.0.7, build afdd53b" ;;
          images) echo "sha256abc123\tsome-size\t3 days ago" ;;
          volume) [ "$2" = "ls" ] && echo "orphan-vol-1" ;;
          system)
            if [ "$2" = "df" ]; then
              echo '{"Type":"Images","Reclaimable":"800MB (66%)"}'
              echo '{"Type":"Build Cache","Reclaimable":"500MB (100%)"}'
            fi
            ;;
        esac
        exit 0
        """)

        let detector = DockerDetector(environment: ["PATH": binDir])
        let items = try await detector.scan(context: scanContext(roots: [TempHome.make()]))

        let image = items.first { $0.sourceDetectorID == "dev.docker.dangling-image" }
        XCTAssertNotNil(image)
        XCTAssertEqual(image?.path, "docker://image/sha256abc123")
        XCTAssertTrue(image?.reason.contains("WARNING") ?? false)

        let volume = items.first { $0.sourceDetectorID == "dev.docker.dangling-volume" }
        XCTAssertNotNil(volume)
        XCTAssertEqual(volume?.path, "docker://volume/orphan-vol-1")
        XCTAssertTrue(volume?.reason.contains("WARNING") ?? false)

        let buildCache = items.first { $0.sourceDetectorID == "dev.docker.build-cache" }
        XCTAssertNotNil(buildCache)
        XCTAssertTrue(buildCache?.reason.contains("500MB") ?? false)
        XCTAssertTrue(buildCache?.reason.contains("WARNING") ?? false)
    }

    func testEveryDockerFindingCarriesStrongWarning() async throws {
        writeFakeDocker(script: """
        #!/bin/sh
        case "$1" in
          --version) echo "Docker version 24.0.7" ;;
          images) echo "sha256def456\tsome-size\t1 day ago" ;;
          volume) [ "$2" = "ls" ] && echo "another-vol" ;;
          system) [ "$2" = "df" ] && echo '{"Type":"Build Cache","Reclaimable":"1GB (100%)"}' ;;
        esac
        exit 0
        """)

        let detector = DockerDetector(environment: ["PATH": binDir])
        let items = try await detector.scan(context: scanContext(roots: [TempHome.make()]))

        XCTAssertFalse(items.isEmpty)
        for item in items {
            XCTAssertTrue(item.reason.contains("WARNING"), "every Docker finding must carry an explicit warning: \(item.reason)")
        }
    }

    func testNeverThrowsEvenWhenDockerBinaryMisbehaves() async throws {
        writeFakeDocker(script: """
        #!/bin/sh
        exit 1
        """)

        let detector = DockerDetector(environment: ["PATH": binDir])
        let items = try await detector.scan(context: scanContext(roots: [TempHome.make()]))
        XCTAssertTrue(items.isEmpty)
    }
}
