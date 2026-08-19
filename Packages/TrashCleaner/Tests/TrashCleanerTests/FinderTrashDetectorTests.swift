import XCTest
import CoreScanEngine
#if canImport(Darwin)
import Darwin
#endif
@testable import TrashCleaner

final class FinderTrashDetectorTests: XCTestCase {
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

    func testFindsBootVolumeTrashItemsAsTopLevelEntries() async throws {
        fm.makeFile(home + "/.Trash/deleted-note.txt")
        fm.makeDir(home + "/.Trash/Old Project")
        fm.makeFile(home + "/.Trash/Old Project/main.swift")

        let detector = FinderTrashDetector(mountedVolumeRoots: { [] })
        let items = try await detector.scan(context: scanContext(roots: [home]))

        let paths = Set(items.map(\.path))
        XCTAssertEqual(paths, [
            home + "/.Trash/Old Project",
            home + "/.Trash/deleted-note.txt"
        ])
        XCTAssertTrue(items.allSatisfy { $0.sourceDetectorID == "trash.finder.boot-volume" })
        XCTAssertTrue(items.allSatisfy { $0.category.contains("boot volume") })
        XCTAssertTrue(items.allSatisfy { !$0.reason.isEmpty })
    }

    func testSkipsDSStoreInTrash() async throws {
        fm.makeFile(home + "/.Trash/.DS_Store")
        fm.makeFile(home + "/.Trash/real-item.txt")

        let detector = FinderTrashDetector(mountedVolumeRoots: { [] })
        let items = try await detector.scan(context: scanContext(roots: [home]))

        XCTAssertEqual(items.map(\.path), [home + "/.Trash/real-item.txt"])
    }

    func testReturnsNoItemsWhenTrashDirMissing() async throws {
        let detector = FinderTrashDetector(mountedVolumeRoots: { [] })
        let items = try await detector.scan(context: scanContext(roots: [home]))
        XCTAssertTrue(items.isEmpty)
    }

    func testComputesRecursiveSizeForDirectoryItems() async throws {
        fm.makeFile(home + "/.Trash/Folder/a.txt", contents: "12345")
        fm.makeFile(home + "/.Trash/Folder/b.txt", contents: "1234567890")

        let detector = FinderTrashDetector(mountedVolumeRoots: { [] })
        let items = try await detector.scan(context: scanContext(roots: [home]))

        let folderItem = try XCTUnwrap(items.first { $0.path == home + "/.Trash/Folder" })
        XCTAssertEqual(folderItem.sizeBytes, 15)
    }

    func testFindsExternalVolumeTrashUnderInjectedMountPoint() async throws {
        let fakeVolume = TempHome.make()
        defer { TempHome.cleanup(fakeVolume) }
        let uid = getuid()
        fm.makeFile(fakeVolume + "/.Trashes/\(uid)/external-deleted.dmg")

        let detector = FinderTrashDetector(mountedVolumeRoots: { [fakeVolume] })
        let items = try await detector.scan(context: scanContext(roots: [home]))

        XCTAssertEqual(items.count, 1)
        let item = try XCTUnwrap(items.first)
        XCTAssertEqual(item.path, fakeVolume + "/.Trashes/\(uid)/external-deleted.dmg")
        XCTAssertEqual(item.sourceDetectorID, "trash.finder.external-volume")
        XCTAssertTrue(item.category.contains((fakeVolume as NSString).lastPathComponent))
    }

    func testDoesNotFindTrashForADifferentUID() async throws {
        let fakeVolume = TempHome.make()
        defer { TempHome.cleanup(fakeVolume) }
        fm.makeFile(fakeVolume + "/.Trashes/99999/not-mine.txt")

        let detector = FinderTrashDetector(mountedVolumeRoots: { [fakeVolume] })
        let items = try await detector.scan(context: scanContext(roots: [home]))

        XCTAssertTrue(items.isEmpty)
    }

    func testCombinesBootVolumeAndExternalVolumeResults() async throws {
        fm.makeFile(home + "/.Trash/local-item.txt")
        let fakeVolume = TempHome.make()
        defer { TempHome.cleanup(fakeVolume) }
        let uid = getuid()
        fm.makeFile(fakeVolume + "/.Trashes/\(uid)/external-item.txt")

        let detector = FinderTrashDetector(mountedVolumeRoots: { [fakeVolume] })
        let items = try await detector.scan(context: scanContext(roots: [home]))

        let paths = Set(items.map(\.path))
        XCTAssertEqual(paths, [
            home + "/.Trash/local-item.txt",
            fakeVolume + "/.Trashes/\(uid)/external-item.txt"
        ])
    }
}
