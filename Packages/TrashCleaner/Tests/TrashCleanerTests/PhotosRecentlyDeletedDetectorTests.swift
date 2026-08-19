import XCTest
import CoreScanEngine
@testable import TrashCleaner

final class PhotosRecentlyDeletedDetectorTests: XCTestCase {
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

    func testReturnsNoItemsWhenNoPhotosLibraryPresent() async throws {
        fm.makeDir(home + "/Pictures")
        let items = try await PhotosRecentlyDeletedDetector().scan(context: scanContext(roots: [home]))
        XCTAssertTrue(items.isEmpty)
    }

    func testReturnsNoItemsWhenPicturesDirMissing() async throws {
        let items = try await PhotosRecentlyDeletedDetector().scan(context: scanContext(roots: [home]))
        XCTAssertTrue(items.isEmpty)
    }

    func testReturnsNoItemsForALibraryWithNoRecognizableTrashResource() async throws {
        fm.makeFile(home + "/Pictures/Photos Library.photoslibrary/originals/1/IMG_0001.heic")
        fm.makeFile(home + "/Pictures/Photos Library.photoslibrary/database/Photos.sqlite")

        let items = try await PhotosRecentlyDeletedDetector().scan(context: scanContext(roots: [home]))

        XCTAssertTrue(items.isEmpty)
    }

    func testFindsRecentlyDeletedLikeResourceByNamePattern() async throws {
        fm.makeFile(home + "/Pictures/Photos Library.photoslibrary/resources/derivatives/RecentlyDeleted/thumb.jpg")

        let items = try await PhotosRecentlyDeletedDetector().scan(context: scanContext(roots: [home]))

        XCTAssertEqual(items.map(\.path), [
            home + "/Pictures/Photos Library.photoslibrary/resources/derivatives/RecentlyDeleted"
        ])
        XCTAssertEqual(items.first?.sourceDetectorID, "trash.photos.recently-deleted")
    }

    func testConsidersEveryPhotoslibraryPackageUnderPictures() async throws {
        fm.makeFile(home + "/Pictures/Second Library.photoslibrary/Trash/deleted.jpg")

        let items = try await PhotosRecentlyDeletedDetector().scan(context: scanContext(roots: [home]))

        XCTAssertEqual(items.map(\.path), [
            home + "/Pictures/Second Library.photoslibrary/Trash"
        ])
    }
}
