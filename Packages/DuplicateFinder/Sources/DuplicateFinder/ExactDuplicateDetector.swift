import CoreScanEngine
import Foundation

/// Finds exact duplicate files (any file type) by content equality.
///
/// **Strategy**, chosen for efficiency on real filesystems with many files:
/// files that differ in size can never be byte-for-byte identical, so this
/// detector first buckets every candidate file by its exact size and only
/// computes a cryptographic content hash (SHA-256, via `CryptoKit`, streamed
/// in fixed-size chunks so large files never need to be fully resident in
/// memory — see `DuplicateFinderFS.sha256Hex(ofFileAt:)`) for files that
/// share their size with at least one other file. A file whose size is
/// unique among the scanned set is never hashed at all.
///
/// **Tie-break rule**: within each resulting hash group (2+ files with
/// byte-identical content), the file with the oldest filesystem
/// modification date is treated as "the original" to keep; ties (or files
/// whose mtime couldn't be read) are broken by sorting paths
/// lexicographically and taking the first. A `ScanItem` is produced for
/// every *other* member of the group — the original itself is never
/// flagged, so this detector only ever proposes the extra copies for
/// cleanup. `reason` names the kept original's path so the user can see
/// exactly why each item was flagged and go verify before removing.
///
/// Strictly read-only: file bytes are read (in order to hash them) but this
/// type never writes, moves, or deletes anything.
public struct ExactDuplicateDetector: Detector {
    public let id = "duplicates.exact"
    public let displayName = "Duplicate Files"
    public let category: DetectorCategory = .duplicates

    /// Files smaller than this are skipped entirely before size-bucketing —
    /// not worth the I/O to hash, and near-certain to produce noisy "false
    /// duplicate" hits from many small files that legitimately share
    /// content (e.g. empty marker files, tiny identical icons).
    private let minFileSizeBytes: Int64

    public init(minFileSizeBytes: Int64 = 4096) {
        self.minFileSizeBytes = minFileSizeBytes
    }

    public func scan(context: ScanContext) async throws -> [ScanItem] {
        let roots = DuplicateFinderRoots.resolve(context)

        var filesBySize: [Int64: [String]] = [:]
        for root in roots {
            if Task.isCancelled { break }
            for entry in DuplicateFinderFS.regularFiles(under: root, isCancelled: { Task.isCancelled }) {
                guard entry.size >= minFileSizeBytes else { continue }
                filesBySize[entry.size, default: []].append(entry.path)
            }
        }

        // Only files that share a size with at least one other file are
        // worth hashing at all.
        let candidatePaths = filesBySize.values.filter { $0.count >= 2 }.flatMap { $0 }
        guard !candidatePaths.isEmpty else { return [] }

        let hashes = await DuplicateFinderFS.sha256Hashes(
            ofFilesAt: candidatePaths,
            maxConcurrency: context.maxConcurrency
        )
        guard !Task.isCancelled else { return [] }

        var filesByHash: [String: [String]] = [:]
        for path in candidatePaths {
            guard let hash = hashes[path] else { continue }
            filesByHash[hash, default: []].append(path)
        }

        var items: [ScanItem] = []
        for group in filesByHash.values where group.count >= 2 {
            if Task.isCancelled { break }
            let sorted = group.sorted { lhs, rhs in
                let lDate = DuplicateFinderFS.modificationDate(lhs)
                let rDate = DuplicateFinderFS.modificationDate(rhs)
                if let lDate, let rDate, lDate != rDate { return lDate < rDate }
                return lhs < rhs
            }
            guard let original = sorted.first else { continue }
            for duplicate in sorted.dropFirst() {
                items.append(ScanItem(
                    path: duplicate,
                    sizeBytes: DuplicateFinderFS.fileSize(duplicate),
                    sourceDetectorID: id,
                    category: "Duplicate file",
                    lastUsed: DuplicateFinderFS.modificationDate(duplicate).map {
                        LastUsedEvidence(date: $0, source: .filesystemMTime)
                    },
                    reason: "Byte-for-byte identical to '\(original)', kept as the original " +
                        "(oldest of \(sorted.count) identical copies found)."
                ))
            }
        }
        return items
    }
}
