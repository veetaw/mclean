import XCTest
import CoreScanEngine
@testable import TrashCleaner

final class MailTrashDetectorTests: XCTestCase {
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

    func testFindsOnMyMacTrashMbox() async throws {
        fm.makeFile(home + "/Library/Mail/V10/Mailboxes/Trash.mbox/Info.plist")

        let items = try await MailTrashDetector().scan(context: scanContext(roots: [home]))

        XCTAssertEqual(items.map(\.path), [home + "/Library/Mail/V10/Mailboxes/Trash.mbox"])
        XCTAssertEqual(items.first?.sourceDetectorID, "trash.mail.mbox")
    }

    func testFindsDeletedMessagesMboxForAnAccount() async throws {
        fm.makeFile(home + "/Library/Mail/V10/SOME-ACCOUNT-UUID/Deleted Messages.mbox/Info.plist")

        let items = try await MailTrashDetector().scan(context: scanContext(roots: [home]))

        XCTAssertEqual(items.map(\.path), [home + "/Library/Mail/V10/SOME-ACCOUNT-UUID/Deleted Messages.mbox"])
    }

    func testIgnoresNonTrashMailboxes() async throws {
        fm.makeFile(home + "/Library/Mail/V10/Mailboxes/INBOX.mbox/Info.plist")
        fm.makeFile(home + "/Library/Mail/V10/Mailboxes/Sent Messages.mbox/Info.plist")

        let items = try await MailTrashDetector().scan(context: scanContext(roots: [home]))

        XCTAssertTrue(items.isEmpty)
    }

    func testDoesNotDescendIntoAMatchedMbox() async throws {
        fm.makeFile(home + "/Library/Mail/V10/Mailboxes/Trash.mbox/Data/1/Messages/1.emlx")

        let items = try await MailTrashDetector().scan(context: scanContext(roots: [home]))

        XCTAssertEqual(items.map(\.path), [home + "/Library/Mail/V10/Mailboxes/Trash.mbox"])
    }

    func testReturnsNoItemsWhenMailDirMissing() async throws {
        let items = try await MailTrashDetector().scan(context: scanContext(roots: [home]))
        XCTAssertTrue(items.isEmpty)
    }
}
