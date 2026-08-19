import XCTest
@testable import RemoteControlServer

final class TokenGeneratorTests: XCTestCase {
    func testGeneratesUniqueTokens() {
        let tokens = Set((0..<200).map { _ in TokenGenerator.generateToken() })
        XCTAssertEqual(tokens.count, 200)
    }

    func testTokenIsURLSafe() {
        let token = TokenGenerator.generateToken()
        XCTAssertFalse(token.contains("+"))
        XCTAssertFalse(token.contains("/"))
        XCTAssertFalse(token.contains("="))
        XCTAssertFalse(token.isEmpty)
    }

    func testHashIsDeterministicAndDistinguishesInputs() {
        let a = TokenGenerator.hash("same-token")
        let b = TokenGenerator.hash("same-token")
        let c = TokenGenerator.hash("different-token")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
        // Hex-encoded SHA-256 -> 64 characters.
        XCTAssertEqual(a.count, 64)
    }
}
