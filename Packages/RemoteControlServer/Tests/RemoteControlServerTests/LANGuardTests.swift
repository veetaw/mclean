import XCTest
@testable import RemoteControlServer

final class LANGuardTests: XCTestCase {
    func testAcceptsPrivateIPv4Ranges() {
        XCTAssertTrue(LANGuard.isLANOrLocalAddress("127.0.0.1"))
        XCTAssertTrue(LANGuard.isLANOrLocalAddress("10.0.0.5"))
        XCTAssertTrue(LANGuard.isLANOrLocalAddress("172.16.0.1"))
        XCTAssertTrue(LANGuard.isLANOrLocalAddress("172.31.255.255"))
        XCTAssertTrue(LANGuard.isLANOrLocalAddress("192.168.1.42"))
        XCTAssertTrue(LANGuard.isLANOrLocalAddress("169.254.1.1"))
    }

    func testRejectsPublicIPv4() {
        XCTAssertFalse(LANGuard.isLANOrLocalAddress("8.8.8.8"))
        XCTAssertFalse(LANGuard.isLANOrLocalAddress("1.1.1.1"))
        XCTAssertFalse(LANGuard.isLANOrLocalAddress("172.32.0.1")) // just outside 172.16/12
        XCTAssertFalse(LANGuard.isLANOrLocalAddress("172.15.255.255"))
        XCTAssertFalse(LANGuard.isLANOrLocalAddress("193.168.1.1")) // not 192.168.x
    }

    func testAcceptsLocalIPv6() {
        XCTAssertTrue(LANGuard.isLANOrLocalAddress("::1"))
        XCTAssertTrue(LANGuard.isLANOrLocalAddress("fe80::1"))
        XCTAssertTrue(LANGuard.isLANOrLocalAddress("fe80::1%en0"))
        XCTAssertTrue(LANGuard.isLANOrLocalAddress("fc00::1"))
        XCTAssertTrue(LANGuard.isLANOrLocalAddress("fd12:3456:789a::1"))
        XCTAssertTrue(LANGuard.isLANOrLocalAddress("::ffff:192.168.1.5"))
    }

    func testRejectsPublicIPv6() {
        XCTAssertFalse(LANGuard.isLANOrLocalAddress("2001:4860:4860::8888")) // Google public DNS
        XCTAssertFalse(LANGuard.isLANOrLocalAddress("::ffff:8.8.8.8"))
        // "fca::1" is NOT in fc00::/7 -- its first group is 0x0fca, not 0xfcxx.
        XCTAssertFalse(LANGuard.isLANOrLocalAddress("fca::1"))
    }

    func testRejectsMissingOrEmptyAddress() {
        XCTAssertFalse(LANGuard.isLANOrLocalAddress(nil))
        XCTAssertFalse(LANGuard.isLANOrLocalAddress(""))
        XCTAssertFalse(LANGuard.isLANOrLocalAddress("not-an-ip"))
    }
}
