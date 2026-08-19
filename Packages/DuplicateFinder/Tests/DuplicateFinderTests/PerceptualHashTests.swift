import XCTest
@testable import DuplicateFinder

final class PerceptualHashTests: XCTestCase {

    func testIdenticalImagesAreConsideredSimilar() {
        let a = makeSolidColorImage(red: 200, green: 60, blue: 60)
        let b = makeSolidColorImage(red: 200, green: 60, blue: 60)

        guard let fa = PerceptualHash.fingerprint(of: a), let fb = PerceptualHash.fingerprint(of: b) else {
            return XCTFail("expected both images to fingerprint")
        }
        XCTAssertEqual(PerceptualHash.hammingDistance(fa.hash, fb.hash), 0)
        XCTAssertTrue(PerceptualHash.areSimilar(fa, fb, maxHammingDistance: 8))
    }

    func testNearIdenticalImagesAreConsideredSimilar() {
        // Same two-tone pattern, but nudged slightly — simulates minor
        // re-compression/color adjustment.
        let a = makeTwoToneImage(leftGray: 40, rightGray: 220)
        let b = makeTwoToneImage(leftGray: 46, rightGray: 214)

        guard let fa = PerceptualHash.fingerprint(of: a), let fb = PerceptualHash.fingerprint(of: b) else {
            return XCTFail("expected both images to fingerprint")
        }
        XCTAssertLessThanOrEqual(PerceptualHash.hammingDistance(fa.hash, fb.hash), 8)
        XCTAssertTrue(PerceptualHash.areSimilar(fa, fb, maxHammingDistance: 8))
    }

    func testSolidBlackVsSolidWhiteAreNotConsideredSimilar() {
        let black = makeSolidColorImage(red: 0, green: 0, blue: 0)
        let white = makeSolidColorImage(red: 255, green: 255, blue: 255)

        guard let fBlack = PerceptualHash.fingerprint(of: black), let fWhite = PerceptualHash.fingerprint(of: white) else {
            return XCTFail("expected both images to fingerprint")
        }

        // A flat/uniform image has zero internal left-right gradient, so
        // the *structural* dHash alone is degenerate here and collides for
        // any two solid colors (documented in `PerceptualHash`'s doc
        // comment) — this is exactly why `ImageFingerprint` also carries
        // average luminance, and `areSimilar` requires both checks to
        // agree before calling two images similar.
        XCTAssertEqual(PerceptualHash.hammingDistance(fBlack.hash, fWhite.hash), 0)
        XCTAssertNotEqual(fBlack.averageLuminance, fWhite.averageLuminance)
        XCTAssertFalse(PerceptualHash.areSimilar(fBlack, fWhite, maxHammingDistance: 8))
    }

    func testDistinctGradientPatternsAreNotConsideredSimilar() {
        // A dark-to-light left-to-right image vs. a light-to-dark
        // left-to-right image are, pixel-for-pixel, near-total inverses of
        // each other under dHash's "left brighter than right" bit test.
        let darkToLight = makeTwoToneImage(leftGray: 10, rightGray: 245)
        let lightToDark = makeTwoToneImage(leftGray: 245, rightGray: 10)

        guard let a = PerceptualHash.fingerprint(of: darkToLight), let b = PerceptualHash.fingerprint(of: lightToDark) else {
            return XCTFail("expected both images to fingerprint")
        }
        // Well above the 8-bit "similar" threshold used elsewhere in this
        // file/the detector's default — the exact value depends on
        // CGContext's downscale interpolation, so this asserts a
        // comfortable margin rather than a precise bit count.
        XCTAssertGreaterThan(PerceptualHash.hammingDistance(a.hash, b.hash), 16)
        XCTAssertFalse(PerceptualHash.areSimilar(a, b, maxHammingDistance: 8))
    }

    func testDecodingFromPNGFileRoundTripsToTheSameFingerprintAsInMemoryImage() throws {
        let root = TempRoot.make()
        defer { TempRoot.cleanup(root) }

        let image = makeSolidColorImage(red: 10, green: 150, blue: 90)
        let path = root + "/photo.png"
        try pngData(for: image).write(to: URL(fileURLWithPath: path))

        guard let inMemory = PerceptualHash.fingerprint(of: image) else {
            return XCTFail("expected in-memory image to fingerprint")
        }
        guard let decoded = PerceptualHash.fingerprint(ofImageAt: path) else {
            return XCTFail("expected PNG file to decode and fingerprint")
        }
        XCTAssertEqual(inMemory, decoded)
    }

    func testUnreadableOrNonImagePathReturnsNil() throws {
        let root = TempRoot.make()
        defer { TempRoot.cleanup(root) }

        let path = root + "/not-an-image.png"
        try "this is plain text, not PNG data".data(using: .utf8)!.write(to: URL(fileURLWithPath: path))

        XCTAssertNil(PerceptualHash.fingerprint(ofImageAt: path))
        XCTAssertNil(PerceptualHash.fingerprint(ofImageAt: root + "/does-not-exist.png"))
    }
}
