import CoreScanEngine
import Foundation

/// Groups visually near-identical images using a perceptual fingerprint.
/// See `PerceptualHash` for exactly which technique (difference hash /
/// dHash, plus an average-luminance check) is used and, importantly, what
/// it can and cannot detect — this is a simple, well-understood,
/// dependency-free technique, not a sophisticated ML-based similarity
/// model.
///
/// **Approach**: enumerate candidate image files under the scan roots
/// (filtered to `PerceptualHash.supportedExtensions`), compute each one's
/// `PerceptualHash.ImageFingerprint`, then compare every pair with
/// `PerceptualHash.areSimilar(_:_:)`. Images considered similar are grouped
/// via a straightforward union-find over the pairwise comparisons. Within
/// each group, the largest file (by size, as a simple proxy for "highest
/// quality/most complete copy") is treated as the one to keep, and a
/// `ScanItem` is produced for every other member, naming the kept file in
/// `reason` and flagging the match as approximate.
///
/// Pairwise comparison is O(n^2) in the number of candidate images; each
/// comparison itself is a cheap XOR + popcount, so this stays practical for
/// realistic personal photo libraries (thousands of images) but is not
/// optimized for huge libraries (a nearest-neighbor index such as a BK-tree
/// or locality-sensitive hashing would be the next step if that becomes a
/// real workload — deferred here as unnecessary complexity for v1).
///
/// Strictly read-only: image bytes are read (in order to decode/hash them)
/// but this type never writes, moves, or deletes anything.
public struct SimilarImageDetector: Detector {
    public let id = "duplicates.similar-images"
    public let displayName = "Similar Photos"
    public let category: DetectorCategory = .duplicates

    /// Structural Hamming distance (out of 64 bits) at or below which two
    /// images' dHashes are considered "similar" — one half of
    /// `PerceptualHash.areSimilar(_:_:)`'s two checks (the other being
    /// average-luminance closeness, not configurable here). 0 means
    /// identical at 8x8 resolution; small values (this default: 8) tolerate
    /// re-compression, resizing, or minor edits without matching unrelated
    /// photos. Kept deliberately conservative to avoid grouping
    /// merely-similar-looking but actually-different photos.
    private let maxHammingDistance: Int

    /// Skip images below this size — thumbnails/icons/tiny assets decode to
    /// near-uniform low-resolution grids that collide with unrelated images
    /// far too easily at any reasonable Hamming threshold.
    private let minFileSizeBytes: Int64

    public init(maxHammingDistance: Int = 8, minFileSizeBytes: Int64 = 8 * 1024) {
        self.maxHammingDistance = maxHammingDistance
        self.minFileSizeBytes = minFileSizeBytes
    }

    public func scan(context: ScanContext) async throws -> [ScanItem] {
        let roots = DuplicateFinderRoots.resolve(context)

        var candidates: [(path: String, size: Int64)] = []
        for root in roots {
            if Task.isCancelled { break }
            for entry in DuplicateFinderFS.regularFiles(under: root, isCancelled: { Task.isCancelled }) {
                guard entry.size >= minFileSizeBytes else { continue }
                let ext = (entry.path as NSString).pathExtension.lowercased()
                guard PerceptualHash.supportedExtensions.contains(ext) else { continue }
                candidates.append(entry)
            }
        }
        guard candidates.count >= 2, !Task.isCancelled else { return [] }

        let fingerprints = await computeFingerprints(for: candidates.map(\.path), maxConcurrency: context.maxConcurrency)
        let hashed = candidates.filter { fingerprints[$0.path] != nil }
        guard hashed.count >= 2, !Task.isCancelled else { return [] }

        let groups = Self.group(hashed, fingerprints: fingerprints, maxHammingDistance: maxHammingDistance)

        var items: [ScanItem] = []
        for members in groups where members.count >= 2 {
            let ranked = members.sorted { $0.size > $1.size }
            guard let kept = ranked.first else { continue }
            for other in ranked.dropFirst() {
                items.append(ScanItem(
                    path: other.path,
                    sizeBytes: other.size,
                    sourceDetectorID: id,
                    category: "Similar photo",
                    lastUsed: DuplicateFinderFS.modificationDate(other.path).map {
                        LastUsedEvidence(date: $0, source: .filesystemMTime)
                    },
                    reason: "Visually similar (perceptual hash, approximate) to '\(kept.path)', kept as the " +
                        "largest of \(ranked.count) similar images found. Verify before removing — this is a " +
                        "pixel-layout fingerprint match, not a guarantee the images are actually the same shot."
                ))
            }
        }
        return items
    }

    /// Groups candidates whose fingerprints are within `maxHammingDistance`
    /// structural bits *and* close in average brightness (see
    /// `PerceptualHash.areSimilar(_:_:)`) of each other, using union-find so
    /// similarity is transitive (A~B and B~C groups A, B, C together even if
    /// A and C individually fall just outside the threshold).
    static func group(
        _ candidates: [(path: String, size: Int64)],
        fingerprints: [String: PerceptualHash.ImageFingerprint],
        maxHammingDistance: Int
    ) -> [[(path: String, size: Int64)]] {
        var parent = Array(0..<candidates.count)
        func find(_ x: Int) -> Int {
            var x = x
            while parent[x] != x {
                parent[x] = parent[parent[x]]
                x = parent[x]
            }
            return x
        }
        func union(_ a: Int, _ b: Int) {
            let ra = find(a), rb = find(b)
            if ra != rb { parent[ra] = rb }
        }

        for i in 0..<candidates.count {
            guard let fi = fingerprints[candidates[i].path] else { continue }
            for j in (i + 1)..<candidates.count {
                guard let fj = fingerprints[candidates[j].path] else { continue }
                if PerceptualHash.areSimilar(fi, fj, maxHammingDistance: maxHammingDistance) {
                    union(i, j)
                }
            }
        }

        var byRoot: [Int: [(path: String, size: Int64)]] = [:]
        for i in 0..<candidates.count {
            byRoot[find(i), default: []].append(candidates[i])
        }
        return Array(byRoot.values)
    }

    private func computeFingerprints(
        for paths: [String],
        maxConcurrency: Int
    ) async -> [String: PerceptualHash.ImageFingerprint] {
        guard !paths.isEmpty else { return [:] }
        let limit = max(1, maxConcurrency)

        return await withTaskGroup(of: (String, PerceptualHash.ImageFingerprint?).self) { group in
            var results: [String: PerceptualHash.ImageFingerprint] = [:]
            var iterator = paths.makeIterator()

            func addNext() {
                guard !Task.isCancelled, let next = iterator.next() else { return }
                group.addTask {
                    (next, PerceptualHash.fingerprint(ofImageAt: next))
                }
            }

            for _ in 0..<limit { addNext() }
            while let (path, fingerprint) = await group.next() {
                if let fingerprint { results[path] = fingerprint }
                addNext()
            }
            return results
        }
    }
}
