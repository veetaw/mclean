import CoreGraphics
import CoreScanEngine
import Foundation
import ImageIO
#if canImport(Darwin)
import Darwin
#endif

/// Test-only helpers for building a throwaway scan root under the system
/// temp directory, so detector logic can be exercised without touching (or
/// depending on the state of) the real machine running the test. Mirrors
/// `DevToolsDetectorsTests.TempHome`.
enum TempRoot {
    static func make() -> String {
        let path = NSTemporaryDirectory() + "DuplicateFinderTests-" + UUID().uuidString
        try! FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        // `NSTemporaryDirectory()` returns the `/var/folders/...` form, but
        // `/var` is itself a symlink to `/private/var` on macOS — and
        // `FileManager.enumerator`/`URL.resourceValues` return the
        // *resolved* `/private/var/...` form. Foundation's
        // `resolvingSymlinksInPath` does *not* resolve this particular
        // symlink (a long-standing quirk carried over from
        // `NSTemporaryDirectory()`'s own historical special-casing), so
        // this canonicalizes via the C library's `realpath(3)` instead,
        // which does. Keeps every expected path built from this root (e.g.
        // `root + "/a.txt"`) byte-for-byte equal to what detectors report.
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    static func cleanup(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }
}

extension FileManager {
    /// Creates every intermediate directory component of `path`.
    func makeDir(_ path: String) {
        try! createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    /// Creates a file at `path` (and any missing parent directories) with
    /// the given raw byte contents.
    func makeFile(_ path: String, contents: Data) {
        makeDir((path as NSString).deletingLastPathComponent)
        try! contents.write(to: URL(fileURLWithPath: path))
    }

    /// Creates a file with the given text contents, repeated `repeatCount`
    /// times, so tests can easily produce files above a detector's minimum
    /// size threshold without hand-authoring large fixtures.
    func makeFile(_ path: String, text: String = "placeholder", repeatCount: Int = 1) {
        let contents = String(repeating: text, count: repeatCount).data(using: .utf8)!
        makeFile(path, contents: contents)
    }

    /// Backdates (or forward-dates) a path's modification time, so tests
    /// can deterministically control "which duplicate is the original"
    /// without sleeping.
    func setModificationDate(_ date: Date, at path: String) {
        try! setAttributes([.modificationDate: date], ofItemAtPath: path)
    }
}

func scanContext(roots: [String], maxConcurrency: Int = 4) -> ScanContext {
    ScanContext(roots: roots, maxConcurrency: maxConcurrency)
}

let testReferenceDate = Date(timeIntervalSince1970: 1_700_000_000)

func daysAgo(_ days: Double, from reference: Date = testReferenceDate) -> Date {
    reference.addingTimeInterval(-days * 24 * 3600)
}

/// Synthesizes a small solid-color `CGImage` in-memory (no disk I/O, no
/// dependency on real photo files existing on the test machine) —
/// `red`/`green`/`blue`/`alpha` each in `0...255`.
func makeSolidColorImage(
    width: Int = 64,
    height: Int = 64,
    red: UInt8,
    green: UInt8,
    blue: UInt8
) -> CGImage {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bytesPerPixel = 4
    var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
    for i in stride(from: 0, to: pixels.count, by: bytesPerPixel) {
        pixels[i] = red
        pixels[i + 1] = green
        pixels[i + 2] = blue
        pixels[i + 3] = 255
    }
    let context = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * bytesPerPixel,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    return context.makeImage()!
}

/// Synthesizes a simple two-tone "checkerboard-ish" pattern: left half one
/// color, right half another. Useful for a perceptual hash that is
/// sensitive to horizontal gradients (dHash compares each pixel to its
/// right neighbor).
func makeTwoToneImage(
    width: Int = 64,
    height: Int = 64,
    leftGray: UInt8,
    rightGray: UInt8
) -> CGImage {
    let colorSpace = CGColorSpaceCreateDeviceGray()
    var pixels = [UInt8](repeating: 0, count: width * height)
    for row in 0..<height {
        for col in 0..<width {
            pixels[row * width + col] = col < width / 2 ? leftGray : rightGray
        }
    }
    let context = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.none.rawValue
    )!
    return context.makeImage()!
}

/// Encodes a `CGImage` to PNG bytes, for tests that want to exercise the
/// file-decoding path (`PerceptualHash.dHash(ofImageAt:)`) end-to-end
/// rather than the in-memory `CGImage` overload.
func pngData(for image: CGImage) -> Data {
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
    return data as Data
}
