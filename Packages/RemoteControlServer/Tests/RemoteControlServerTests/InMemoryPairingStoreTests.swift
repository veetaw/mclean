import XCTest
@testable import RemoteControlServer

final class InMemoryPairingStoreTests: XCTestCase {
    func testSaveAndLookupDeviceByTokenHash() async {
        let store = InMemoryPairingStore()
        let device = PairedDevice(displayName: "iPhone", tokenHash: TokenGenerator.hash("secret-token"))
        await store.saveDevice(device)

        let found = await store.device(forTokenHash: TokenGenerator.hash("secret-token"))
        XCTAssertEqual(found?.id, device.id)

        let notFound = await store.device(forTokenHash: TokenGenerator.hash("wrong-token"))
        XCTAssertNil(notFound)
    }

    func testRevokedDeviceIsNoLongerFoundByToken() async {
        let store = InMemoryPairingStore()
        let device = PairedDevice(displayName: "iPad", tokenHash: TokenGenerator.hash("t"))
        await store.saveDevice(device)
        await store.revokeDevice(id: device.id)

        let found = await store.device(forTokenHash: TokenGenerator.hash("t"))
        XCTAssertNil(found)

        let byID = await store.device(forID: device.id)
        XCTAssertNotNil(byID?.revokedAt)
    }

    func testInvitationIsSingleUse() async {
        let store = InMemoryPairingStore()
        let hash = TokenGenerator.hash("invite")
        let record = PairingInvitationRecord(tokenHash: hash, createdAt: Date(), expiresAt: Date().addingTimeInterval(300))
        await store.saveInvitation(record)

        let firstUse = await store.consumeInvitation(tokenHash: hash, now: Date())
        XCTAssertNotNil(firstUse)

        let secondUse = await store.consumeInvitation(tokenHash: hash, now: Date())
        XCTAssertNil(secondUse, "an invitation must not be redeemable twice")
    }

    func testExpiredInvitationIsRejected() async {
        let store = InMemoryPairingStore()
        let hash = TokenGenerator.hash("invite-2")
        let past = Date().addingTimeInterval(-10)
        let record = PairingInvitationRecord(tokenHash: hash, createdAt: past.addingTimeInterval(-300), expiresAt: past)
        await store.saveInvitation(record)

        let result = await store.consumeInvitation(tokenHash: hash, now: Date())
        XCTAssertNil(result)
    }

    func testAllDevicesSortedByPairedAt() async {
        let store = InMemoryPairingStore()
        let older = PairedDevice(displayName: "Old", tokenHash: "a", pairedAt: Date().addingTimeInterval(-100))
        let newer = PairedDevice(displayName: "New", tokenHash: "b", pairedAt: Date())
        await store.saveDevice(newer)
        await store.saveDevice(older)

        let all = await store.allDevices()
        XCTAssertEqual(all.map(\.displayName), ["Old", "New"])
    }
}
