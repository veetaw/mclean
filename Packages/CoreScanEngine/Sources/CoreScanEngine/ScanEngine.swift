import Foundation

/// Runs a set of registered `Detector`s concurrently (bounded by
/// `ScanContext.maxConcurrency`) and aggregates their findings.
///
/// `ScanEngine` never deletes anything — it is purely the "find" half of the
/// pipeline. Classification of what's safe to touch belongs to `SafetyRules`,
/// and actual deletion (behind confirmation + quarantine) belongs to a module
/// that does not exist yet pending the checkpoint 2 discussion with the user.
public actor ScanEngine {
    private var detectors: [Detector] = []

    public init() {}

    public func register(_ detector: Detector) {
        detectors.append(detector)
    }

    public func register(_ newDetectors: [Detector]) {
        detectors.append(contentsOf: newDetectors)
    }

    /// Runs every registered detector concurrently and returns the merged
    /// results, tagged with which detector produced them (already embedded in
    /// `ScanItem.sourceDetectorID`). Errors from individual detectors are
    /// collected rather than aborting the whole scan.
    public func runAll(context: ScanContext) async -> ScanRunResult {
        // Per-detector outcome, captured without the `Error` existential
        // (which is not guaranteed `Sendable`) so this crosses task
        // boundaries cleanly under Swift 6 strict concurrency.
        enum Outcome: Sendable {
            case success([ScanItem])
            case failure(String)
        }

        return await withTaskGroup(of: (String, Outcome).self) { group in
            for detector in detectors {
                group.addTask {
                    do {
                        let items = try await detector.scan(context: context)
                        return (detector.id, .success(items))
                    } catch {
                        return (detector.id, .failure(String(describing: error)))
                    }
                }
            }

            var items: [ScanItem] = []
            var failures: [String: String] = [:]
            for await (detectorID, outcome) in group {
                switch outcome {
                case .success(let found):
                    items.append(contentsOf: found)
                case .failure(let description):
                    failures[detectorID] = description
                }
            }
            return ScanRunResult(items: items, failedDetectorIDs: failures)
        }
    }
}

public struct ScanRunResult: Sendable {
    public let items: [ScanItem]
    /// Detector ID -> error description, for detectors that threw during this run.
    public let failedDetectorIDs: [String: String]

    public init(items: [ScanItem], failedDetectorIDs: [String: String]) {
        self.items = items
        self.failedDetectorIDs = failedDetectorIDs
    }
}

extension ScanRunResult: CustomStringConvertible {
    public var description: String {
        "ScanRunResult(items: \(items.count), failedDetectors: \(failedDetectorIDs.keys.sorted()))"
    }
}
