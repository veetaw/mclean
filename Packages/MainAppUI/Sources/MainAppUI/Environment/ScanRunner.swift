import CoreScanEngine
import Foundation
import Observation

/// Shared, app-lifetime scan execution + progress state, owned by
/// `AppEnvironment`.
///
/// ROOT CAUSE this fixes ("scans stop when switching tabs"): this was
/// **not** a `Task` cancellation bug. Both `DashboardView` and
/// `FindingsListView` kick off scans with a bare `Task { await scanNow() }`
/// inside a button action, not a `.task { }` view modifier — SwiftUI only
/// auto-cancels the latter when its view disappears, so the scan `Task`
/// itself genuinely kept running in the background the whole time. The real
/// bug was that `isScanning`/`findings`/`lastScanFinishedAt` all lived in
/// each view's own `@State`. `ContentView.detailView(for:)` is a
/// `@ViewBuilder switch` that tears down and reconstructs a brand-new
/// `DashboardView`/`FindingsListView` value (with fresh, default `@State`)
/// every time the sidebar selection changes — so navigating away and back
/// mid-scan produced a view with `isScanning == false` again, even though a
/// scan was still silently running underneath. That reads exactly like "the
/// scan stopped" without it ever actually being cancelled.
///
/// The fix: move this state up to `AppEnvironment` scope, which is
/// constructed once per app launch and injected via `.environment(environment)`
/// — it already survives every navigation change, same as
/// `AppEnvironment.scanSnapshotStore` already does for scan *results*. Any
/// view can now observe `isScanning`/`progress` via
/// `@Environment(AppEnvironment.self)` instead of keeping a local copy that
/// resets when its view is recreated.
@MainActor
@Observable
public final class ScanRunner {
    /// True while a `run(engine:context:onFinished:)` call is in flight.
    public private(set) var isScanning = false

    /// Completion-count-based progress across every registered detector,
    /// 0...1. **This is not wall-clock/time-based** — it's "detectors
    /// finished / detectors registered", updated once per detector as its
    /// `ScanEngine.runAll` `TaskGroup` child task returns (see
    /// `ScanEngine.runAll`'s doc comment). Detectors vary hugely in how long
    /// they take (a full-disk duplicate walk vs. a single plist read), so
    /// this fraction is not linear with elapsed time — treat it as "how much
    /// of the work queue is done", not an ETA.
    public private(set) var progress: Double = 0
    public private(set) var completedDetectorCount = 0
    public private(set) var totalDetectorCount = 0

    /// Per-`DetectorCategory` completion breakdown for the in-progress (or
    /// most recently finished) scan, e.g. Developer Tools 6/10. Populated
    /// with `0/N` totals as soon as `run` starts (from `ScanEngine
    /// .registeredDetectorCounts()`), then incremented as each detector in
    /// that category completes. Reset at the start of every `run` call.
    public private(set) var categoryProgress: [DetectorCategory: CategoryProgress] = [:]

    /// Mirrors the timestamp `AppEnvironment` records into
    /// `scanSnapshotStore` after classifying a finished run — kept here too
    /// so views can read it synchronously (no `await`) as part of this same
    /// `@Observable` object, right alongside `isScanning`/`progress`.
    public private(set) var lastScanFinishedAt: Date?

    /// The in-flight scan task, if any. A second call to `run` while one is
    /// already running **joins** this task instead of starting a duplicate,
    /// concurrent scan — guards against e.g. a double-tap on "Rescan"
    /// double-running detectors and racing on `scanSnapshotStore`.
    private var runningTask: Task<ScanRunResult, Never>?

    public init() {}

    public struct CategoryProgress: Sendable, Equatable {
        public var completed: Int
        public var total: Int
        public init(completed: Int, total: Int) {
            self.completed = completed
            self.total = total
        }
        public var fraction: Double { total == 0 ? 1.0 : Double(completed) / Double(total) }
    }

    /// Runs (or joins an already-running) full scan through `engine`,
    /// updating `isScanning`/`progress`/`categoryProgress` as detectors
    /// complete, then awaits `onFinished` (where the caller is expected to
    /// classify results and record them into e.g. `ScanSnapshotStore`)
    /// before flipping `isScanning` back to `false` — so by the time any
    /// observer sees `isScanning == false`, downstream state has already
    /// been updated, not just the raw scan.
    @discardableResult
    public func run(
        engine: ScanEngine,
        context: ScanContext,
        onFinished: @MainActor (ScanRunResult) async -> Void
    ) async -> ScanRunResult {
        if let runningTask {
            // Another caller already has a scan in flight — join it rather
            // than starting a second, concurrent `runAll`.
            return await runningTask.value
        }

        let counts = await engine.registeredDetectorCounts()
        isScanning = true
        completedDetectorCount = 0
        totalDetectorCount = counts.total
        progress = 0
        categoryProgress = counts.byCategory.mapValues { CategoryProgress(completed: 0, total: $0) }

        let task = Task<ScanRunResult, Never> { [weak self] in
            await engine.runAll(context: context) { event in
                await MainActor.run {
                    self?.apply(event)
                }
            }
        }
        runningTask = task

        let result = await task.value
        runningTask = nil
        await onFinished(result)
        isScanning = false
        lastScanFinishedAt = Date()
        return result
    }

    private func apply(_ event: ScanProgress) {
        completedDetectorCount = event.completedCount
        totalDetectorCount = event.totalCount
        progress = event.fraction
        var entry = categoryProgress[event.category] ?? CategoryProgress(completed: 0, total: 0)
        entry.completed += 1
        categoryProgress[event.category] = entry
    }
}
