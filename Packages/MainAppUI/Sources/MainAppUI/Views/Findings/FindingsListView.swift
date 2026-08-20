import CoreScanEngine
import RemoteControlServer
import SafetyRules
import SwiftUI
import UIDesignSystem

/// Reusable findings list, backed by the real `AppEnvironment.scanEngine` +
/// `SafetyClassifier` + `FileSystemQuarantineManager`, shared by the
/// Developer Tools, Mobile Dev, and Power User sidebar sections. Each
/// caller supplies which detector IDs it cares about; the view reads (and
/// filters) `AppEnvironment.scanSnapshotStore`'s current snapshot rather
/// than owning its own scan state, so every section reflects the same
/// last-scan results the Remote Control server would also report.
@available(macOS 26.0, *)
struct FindingsListView: View {
    let title: String
    let systemImage: String
    let emptyStateMessage: String
    /// `CoreScanEngine.Detector.id` values this section should display.
    /// `nil` means "show everything in the current snapshot" (used by the
    /// Dashboard's own summary, not by the per-category sections).
    let detectorIDs: Set<String>?

    @Environment(AppEnvironment.self) private var environment

    @State private var findings: [ScanFinding] = []
    @State private var lastScanFinishedAt: Date?
    // `isScanning` is intentionally NOT local `@State` — it reads
    // `environment.scanRunner.isScanning` directly (see `ScanRunner`'s doc
    // comment). Local `@State` here is exactly what caused "scans stop when
    // switching tabs": `ContentView.detailView(for:)` recreates this view
    // (with fresh `@State`) on every sidebar navigation, so a locally-owned
    // scanning flag silently reset to `false` even while the scan `Task`
    // kept running unseen in the background. Reading it from `AppEnvironment`
    // (constructed once, alive for the app's lifetime) means every section
    // sees the same in-progress state regardless of which view started the
    // scan or which view is currently visible.
    private var isScanning: Bool { environment.scanRunner.isScanning }
    // Stores the `Identifiable` sheet item itself (created once, at the
    // moment the user taps an action), not just the raw `[ScanFinding]`
    // batch. Previously this was `[ScanFinding]?` and `.sheet(item:)` was
    // fed through a computed `Binding` whose `get` closure ran
    // `pendingQuarantine.map(QuarantineBatch.init)` — `QuarantineBatch.init`
    // assigns `id = UUID()`, so *every* SwiftUI body re-evaluation while the
    // sheet was open (e.g. `isQuarantining` flipping to true the instant the
    // user tapped "Move to Quarantine") produced a fresh random id for the
    // "same" batch. `.sheet(item:)` uses that id to decide whether it's
    // still showing the same sheet or swapping to a new one, so the sheet
    // could flicker/reset (or, on some SwiftUI versions, silently fail to
    // reflect the in-progress state) right at the moment of confirmation.
    // Storing the already-identified batch directly in `@State` and binding
    // to it with plain `$pendingQuarantine` gives the sheet a stable id for
    // as long as the same batch is pending, regardless of how many times
    // this view's body re-evaluates in between.
    @State private var pendingQuarantine: QuarantineBatch?
    @State private var isQuarantining = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.large) {
            header

            if findings.isEmpty {
                emptyState
            } else {
                resultsList
            }
        }
        .padding(DSSpacing.xLarge)
        .task { await refresh() }
        // A scan started from *this* view, another view, or the Dashboard
        // all funnel through the same `environment.scanRunner` — when it
        // flips back to not-scanning, re-pull the snapshot so this view's
        // list reflects the just-finished results without requiring the
        // user to navigate away and back (which would previously have been
        // the only way to see anything change).
        .onChange(of: environment.scanRunner.isScanning) { _, nowScanning in
            if !nowScanning {
                Task { await refresh() }
            }
        }
        .sheet(item: $pendingQuarantine) { batch in
            QuarantineConfirmationSheet(
                findings: batch.findings,
                isWorking: isQuarantining,
                onConfirm: { Task { await performQuarantine(batch.findings) } },
                onCancel: { pendingQuarantine = nil }
            )
        }
        .alert("Couldn't complete that action", isPresented: errorAlertBinding) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: DSSpacing.small) {
            // `ModuleHeroHeader` gives this landing screen the same icon
            // badge + large-title treatment as every other module (see the
            // component's doc comment) — this replaces the previous bare
            // `Label(...).font(.largeTitle)`, the row of controls is now the
            // header's `accessory` instead of a hand-rolled `HStack`. Purely
            // presentational: still the same `Rescan`/`Clean Safe Items`
            // actions and the same `isScanning`/`safeAutoEligible` state.
            ModuleHeroHeader(title: title, systemImage: systemImage) {
                GlassControlGroup {
                    Button("Rescan", systemImage: "arrow.clockwise") {
                        Task { await scanNow() }
                    }
                    .dsButtonStyle(.secondary)
                    .disabled(isScanning)

                    if !safeAutoEligible.isEmpty {
                        Button("Clean Safe Items (\(safeAutoEligible.count))", systemImage: "checkmark.seal") {
                            pendingQuarantine = QuarantineBatch(findings: safeAutoEligible)
                        }
                        .dsButtonStyle(.primary)
                        .disabled(isScanning)
                    }
                }
            }

            // Reads `environment.scanRunner.progress` inside its own `body`,
            // not this view's — `progress` ticks far more often than any
            // other state here (see `ScanRunner`), and `@Observable`
            // invalidates whichever `View.body` actually read the changed
            // property. If this HStack were still inlined into
            // `FindingsListView.body` directly, every tick would invalidate
            // and re-diff the *entire* body, including `resultsList`'s
            // hundreds of rows, not just this status line. Isolating the
            // read here keeps a tick's invalidation scoped to this one small
            // subview.
            ScanProgressStatus(
                lastScanFinishedAt: lastScanFinishedAt,
                totalReclaimableBytes: totalReclaimableBytes,
                findingsCount: findings.count
            )
        }
    }

    // A "nothing scanned yet" state and a "we scanned and found nothing"
    // state read as different situations to a user (the first invites a
    // first scan, the second is reassuring) — `ModuleEmptyStateCard` renders
    // both through the same shape, but the headline/tint/CTA below vary by
    // `lastScanFinishedAt` so each reads correctly.
    private var emptyState: some View {
        ModuleEmptyStateCard(
            systemImage: lastScanFinishedAt == nil ? "sparkle.magnifyingglass" : "checkmark.seal",
            headline: lastScanFinishedAt == nil ? "Nothing Scanned Yet" : "All Clear",
            message: emptyStateMessage,
            tint: lastScanFinishedAt == nil ? DSColor.accent : DSColor.safe,
            actionLabel: lastScanFinishedAt == nil ? "Scan Now" : "Rescan",
            actionSystemImage: lastScanFinishedAt == nil ? "sparkle.magnifyingglass" : "arrow.clockwise",
            isActionDisabled: isScanning
        ) {
            Task { await scanNow() }
        }
    }

    private var resultsList: some View {
        GlassCard(padding: 0) {
            // `LazyVStack`, not `VStack` — a plain `VStack` inside a
            // `ScrollView` builds and lays out every row up front regardless
            // of what's actually visible, which is the classic SwiftUI
            // virtualization trap for long lists: System Junk scans
            // routinely produce hundreds of findings, so a plain `VStack`
            // here means scrolling has to push around hundreds of already-
            // materialized `ScanResultRow`s at once. `LazyVStack` only
            // instantiates rows near the visible viewport, which is what
            // actually fixes the scroll lag (this is a structural fix, not
            // something a formatting-cost microbenchmark would show — see
            // the perf notes alongside this task).
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(findings) { finding in
                        ScanResultRow(
                            systemImage: rowIcon(for: finding),
                            icon: ScanItemRowDisplay.icon(for: finding.item),
                            title: ScanItemRowDisplay.title(for: finding.item),
                            subtitle: finding.item.path,
                            sizeBytes: finding.item.sizeBytes,
                            safetyTier: finding.verdict.uiTier,
                            actionLabel: finding.verdict.isEligibleForQuarantine ? "Quarantine" : "Locked",
                            actionVariant: finding.verdict.isEligibleForQuarantine ? .secondary : .destructive
                        ) {
                            pendingQuarantine = QuarantineBatch(findings: [finding])
                        }
                        .disabled(!finding.verdict.isEligibleForQuarantine)

                        if finding.id != findings.last?.id {
                            Divider().opacity(0.3)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private var safeAutoEligible: [ScanFinding] {
        findings.filter {
            if case .safeAuto = $0.verdict { return true }
            return false
        }
    }

    private var totalReclaimableBytes: Int64 {
        findings.reduce(Int64(0)) { $0 + ($1.item.sizeBytes ?? 0) }
    }

    private func rowIcon(for finding: ScanFinding) -> String {
        switch finding.verdict {
        case .forbidden: "lock.shield.fill"
        case .safeAuto: "checkmark.seal"
        case .needsConfirmation: "exclamationmark.triangle"
        }
    }

    // MARK: - Actions

    private func refresh() async {
        let snapshot = await environment.scanSnapshotStore.currentSnapshot()
        lastScanFinishedAt = snapshot.lastScanFinishedAt
        applySnapshot(snapshot)
    }

    private func applySnapshot(_ snapshot: ScanSnapshot) {
        if let detectorIDs {
            findings = snapshot.findings.filter { detectorIDs.contains($0.item.sourceDetectorID) }
        } else {
            findings = snapshot.findings
        }
    }

    private func scanNow() async {
        // `environment.runFullScan()` itself guards against duplicate
        // concurrent scans (see `ScanRunner.run`) and drives
        // `environment.scanRunner.isScanning`/`progress` for the duration —
        // nothing to track locally here.
        await environment.runFullScan()
        await refresh()
    }

    private func performQuarantine(_ batch: [ScanFinding]) async {
        isQuarantining = true
        defer { isQuarantining = false }

        var failures: [String] = []
        for finding in batch {
            do {
                _ = try await environment.quarantineManager.quarantine(finding.item, retention: .default)
            } catch {
                failures.append("\(finding.item.path): \(error)")
            }
        }

        pendingQuarantine = nil
        if !failures.isEmpty {
            errorMessage = failures.joined(separator: "\n")
        }
        // Re-run a full scan so the snapshot (and any Remote Control
        // clients reading it) reflects what's actually still on disk,
        // rather than optimistically mutating local state.
        await scanNow()
    }

    // MARK: - Sheet item plumbing

    private struct QuarantineBatch: Identifiable {
        let id = UUID()
        let findings: [ScanFinding]
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
}

/// The "Scanning… NN% (x/y detectors)" / "Last scan: …" / "No scan yet…"
/// status line, split out of `FindingsListView.header` specifically so it
/// alone re-renders when `environment.scanRunner.progress` ticks — see the
/// call site's comment for why that matters for scroll performance.
@available(macOS 26.0, *)
private struct ScanProgressStatus: View {
    let lastScanFinishedAt: Date?
    let totalReclaimableBytes: Int64
    let findingsCount: Int

    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        HStack(spacing: DSSpacing.small) {
            if environment.scanRunner.isScanning {
                ProgressView(value: environment.scanRunner.progress).controlSize(.small).frame(width: 80)
                // Completion-count-based, not time-based — see
                // `ScanRunner.progress`'s doc comment.
                Text("Scanning… \(Int(environment.scanRunner.progress * 100))% (\(environment.scanRunner.completedDetectorCount)/\(environment.scanRunner.totalDetectorCount) detectors)")
                    .font(DSTypography.subheading)
                    .foregroundStyle(DSColor.textSecondary)
            } else if let lastScanFinishedAt {
                Text("Last scan: \(lastScanFinishedAt.formatted(date: .abbreviated, time: .shortened)) · \(ScanResultRow.formattedSize(totalReclaimableBytes)) reclaimable across \(findingsCount) items")
                    .font(DSTypography.subheading)
                    .foregroundStyle(DSColor.textSecondary)
            } else {
                Text("No scan yet — tap Rescan to look for findings.")
                    .font(DSTypography.subheading)
                    .foregroundStyle(DSColor.textSecondary)
            }
        }
    }
}
