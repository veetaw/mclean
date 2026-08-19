import CoreGraphics
import Foundation
import ImageIO

/// A simple, self-contained perceptual image fingerprint built from
/// **difference hash (dHash)** plus an average-luminance check. This is a
/// well-understood, purely local, dependency-free technique for finding
/// *visually near-identical* images — it is deliberately not, and does not
/// claim to be, a sophisticated ML-based similarity model (no Vision
/// framework feature prints, no on-device model, no semantic/content
/// understanding).
///
/// **Structural component (dHash)**: an image is downscaled to a fixed
/// small grayscale grid (9x8 pixels — one extra column so each row yields 8
/// adjacent-pixel comparisons), and each pixel is compared to its immediate
/// right neighbor. "Left brighter than right" becomes a `1` bit, otherwise
/// `0`, producing a 64-bit fingerprint. Two images whose fingerprints
/// differ in only a few bits (small Hamming distance) look visually
/// similar at low resolution — typically the same photo re-saved, resized,
/// lightly re-compressed, or minorly color/exposure-adjusted.
///
/// **Why an average-luminance check is also needed**: dHash (like aHash)
/// encodes only *relative* structure, not absolute brightness — it is
/// invariant to any transformation that preserves each pixel's ordering
/// relative to its neighbors. A degenerate but real consequence: two
/// perfectly flat/uniform images (e.g. a solid black frame and a solid
/// white frame) have *zero* internal gradient either way and hash
/// identically under dHash alone, even though they are obviously
/// different. `ImageFingerprint` therefore also carries each image's mean
/// grayscale value, and `areSimilar(_:_:)` requires both the structural
/// hash *and* the average brightness to be close before calling two images
/// similar — still a simple, local, explainable check, just not a
/// single-number one.
///
/// What this technique deliberately does **not** do: recognize the same
/// subject reframed, cropped very differently, rotated, mirrored, or shot
/// from a different angle — it is a pixel-layout fingerprint, not
/// object/scene recognition. It is chosen here specifically because it is
/// simple, fast, needs no model weights or network access, and is good
/// enough to flag the common "burst-mode duplicate" / "re-exported copy"
/// case that dominates real photo libraries — not because it is the most
/// accurate technique available.
enum PerceptualHash {
    /// Raster image extensions (lowercased, no dot) this detector
    /// considers. `ImageIO`'s `CGImageSourceCreateWithURL` decodes all of
    /// these without any format-specific code. RAW formats, vector
    /// formats, and video are intentionally out of scope.
    static let supportedExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "tiff", "tif", "gif", "bmp"]

    struct ImageFingerprint: Sendable, Equatable {
        /// 64-bit structural dHash.
        let hash: UInt64
        /// Mean grayscale value (0...255) of the same downscaled grid used
        /// to compute `hash`.
        let averageLuminance: UInt8
    }

    /// Decodes the image file at `path` and computes its fingerprint.
    /// Returns `nil` for unreadable, corrupt, or non-image files rather
    /// than throwing, so one bad file doesn't abort a whole scan.
    static func fingerprint(ofImageAt path: String) -> ImageFingerprint? {
        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return fingerprint(of: cgImage)
    }

    /// Computes the fingerprint of an already-decoded `CGImage`. Exposed
    /// separately from `fingerprint(ofImageAt:)` so tests can exercise it
    /// against small synthetic images built in-memory with `CGContext`,
    /// without needing real image files on disk.
    static func fingerprint(of cgImage: CGImage, gridWidth: Int = 9, gridHeight: Int = 8) -> ImageFingerprint? {
        guard gridWidth >= 2, gridHeight >= 1, gridWidth * gridHeight <= 64 + gridHeight else { return nil }
        guard let pixels = grayscalePixels(of: cgImage, width: gridWidth, height: gridHeight) else { return nil }

        var hash: UInt64 = 0
        var bit = 0
        for row in 0..<gridHeight {
            for col in 0..<(gridWidth - 1) {
                let left = pixels[row * gridWidth + col]
                let right = pixels[row * gridWidth + col + 1]
                if left > right {
                    hash |= (UInt64(1) << UInt64(bit))
                }
                bit += 1
            }
        }

        let sum = pixels.reduce(0) { $0 + Int($1) }
        let average = UInt8(clamping: sum / pixels.count)
        return ImageFingerprint(hash: hash, averageLuminance: average)
    }

    /// Renders `cgImage`, resampled, into an 8-bit grayscale `width` x
    /// `height` pixel buffer. Uses an explicitly-owned raw buffer (rather
    /// than handing `CGContext` a pointer derived from a Swift `Array`'s
    /// storage) so the backing memory is guaranteed valid for the whole
    /// time `CGContext` holds onto it.
    static func grayscalePixels(of cgImage: CGImage, width: Int, height: Int) -> [UInt8]? {
        let bufferSize = width * height
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        buffer.initialize(repeating: 0, count: bufferSize)

        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(
            data: buffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return Array(UnsafeBufferPointer(start: buffer, count: bufferSize))
    }

    /// Number of differing bits between two structural hashes — the
    /// standard similarity measure for dHash/aHash-style fingerprints. 0 =
    /// identical structure; higher = more visually different layout.
    static func hammingDistance(_ a: UInt64, _ b: UInt64) -> Int {
        (a ^ b).nonzeroBitCount
    }

    /// Whether two fingerprints should be considered "similar": their
    /// structural hashes must be within `maxHammingDistance` bits AND their
    /// average brightness must be within `maxAverageLuminanceDelta` of each
    /// other. Both checks are needed — see the type-level doc comment for
    /// why the structural hash alone isn't sufficient (flat/uniform images
    /// of different colors hash identically under dHash).
    static func areSimilar(
        _ a: ImageFingerprint,
        _ b: ImageFingerprint,
        maxHammingDistance: Int,
        maxAverageLuminanceDelta: Int = 24
    ) -> Bool {
        guard hammingDistance(a.hash, b.hash) <= maxHammingDistance else { return false }
        return abs(Int(a.averageLuminance) - Int(b.averageLuminance)) <= maxAverageLuminanceDelta
    }
}
