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

    /// How many detectors are currently registered, overall and per
    /// `DetectorCategory`. Callers that want to show progress *before* a
    /// scan starts (e.g. to pre-populate a per-category "0/N" breakdown)
    /// should read this first, since `runAll`'s progress callback only
    /// fires once detectors start completing.
    public func registeredDetectorCounts() -> (total: Int, byCategory: [DetectorCategory: Int]) {
        var byCategory: [DetectorCategory: Int] = [:]
        for detector in detectors {
            byCategory[detector.category, default: 0] += 1
        }
        return (detectors.count, byCategory)
    }

    /// Runs every registered detector concurrently and returns the merged
    /// results, tagged with which detector produced them (already embedded in
    /// `ScanItem.sourceDetectorID`). Errors from individual detectors are
    /// collected rather than aborting the whole scan.
    ///
    /// `onProgress`, if provided, is invoked once per detector as its
    /// `TaskGroup` child task completes (success or failure), reporting how
    /// many of the registered detectors are done so far. This is
    /// **completion-count-based progress, not time-based**: individual
    /// detectors are not instrumented internally, so a detector that walks
    /// the whole disk and one that reads a single plist both count as "one
    /// completed detector" — the resulting fraction is an honest measure of
    /// "how much of the work queue is done", not a linear ETA. The callback
    /// runs on this actor (no extra hop needed to read `self` state), but is
    /// itself `@Sendable`/`async` so a caller can freely hop to another
    /// actor (e.g. `@MainActor`) inside it to update UI state.
    public func runAll(
        context: ScanContext,
        onProgress: (@Sendable (ScanProgress) async -> Void)? = nil
    ) async -> ScanRunResult {
        // Per-detector outcome, captured without the `Error` existential
        // (which is not guaranteed `Sendable`) so this crosses task
        // boundaries cleanly under Swift 6 strict concurrency.
        enum Outcome: Sendable {
            case success([ScanItem])
            case failure(String)
        }

        let total = detectors.count

        return await withTaskGroup(of: (String, DetectorCategory, Outcome).self) { group in
            for detector in detectors {
                group.addTask {
                    do {
                        let items = try await detector.scan(context: context)
                        return (detector.id, detector.category, .success(items))
                    } catch {
                        return (detector.id, detector.category, .failure(String(describing: error)))
                    }
                }
            }

            var items: [ScanItem] = []
            var failures: [String: String] = [:]
            var completed = 0
            for await (detectorID, category, outcome) in group {
                switch outcome {
                case .success(let found):
                    items.append(contentsOf: found)
                case .failure(let description):
                    failures[detectorID] = description
                }
                completed += 1
                if let onProgress {
                    await onProgress(
                        ScanProgress(
                            completedDetectorID: detectorID,
                            category: category,
                            completedCount: completed,
                            totalCount: total
                        )
                    )
                }
            }
            return ScanRunResult(items: items, failedDetectorIDs: failures)
        }
    }
}

/// One detector-completion event during a `ScanEngine.runAll` call — see
/// that method's doc comment for why this is completion-count-based rather
/// than time-based progress.
public struct ScanProgress: Sendable {
    public let completedDetectorID: String
    public let category: DetectorCategory
    /// How many registered detectors have completed so far, including this one.
    public let completedCount: Int
    /// Total detectors registered for this run.
    public let totalCount: Int

    public init(completedDetectorID: String, category: DetectorCategory, completedCount: Int, totalCount: Int) {
        self.completedDetectorID = completedDetectorID
        self.category = category
        self.completedCount = completedCount
        self.totalCount = totalCount
    }

    /// Fraction of registered detectors completed so far, 0...1. `1.0` when
    /// there are no registered detectors (nothing left to wait for).
    public var fraction: Double {
        totalCount == 0 ? 1.0 : Double(completedCount) / Double(totalCount)
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
