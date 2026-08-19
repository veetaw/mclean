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
    @State private var isScanning = false
    @State private var lastScanFinishedAt: Date?
    @State private var pendingQuarantine: [ScanFinding]?
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
        .sheet(item: pendingQuarantineBinding) { batch in
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
            HStack {
                Label(title, systemImage: systemImage)
                    .font(DSTypography.largeTitle)
                Spacer()
                GlassControlGroup {
                    Button("Rescan", systemImage: "arrow.clockwise") {
                        Task { await scanNow() }
                    }
                    .dsButtonStyle(.secondary)
                    .disabled(isScanning)

                    if !safeAutoEligible.isEmpty {
                        Button("Clean Safe Items (\(safeAutoEligible.count))", systemImage: "checkmark.seal") {
                            pendingQuarantine = safeAutoEligible
                        }
                        .dsButtonStyle(.primary)
                        .disabled(isScanning)
                    }
                }
            }

            HStack(spacing: DSSpacing.small) {
                if isScanning {
                    ProgressView().controlSize(.small)
                    Text("Scanning…")
                        .font(DSTypography.subheading)
                        .foregroundStyle(DSColor.textSecondary)
                } else if let lastScanFinishedAt {
                    Text("Last scan: \(lastScanFinishedAt.formatted(date: .abbreviated, time: .shortened)) · \(ScanResultRow.formattedSize(totalReclaimableBytes)) reclaimable across \(findings.count) items")
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

    private var emptyState: some View {
        GlassCard {
            VStack(spacing: DSSpacing.small) {
                Image(systemName: "checkmark.circle")
                    .font(.largeTitle)
                    .foregroundStyle(DSColor.safe)
                Text(emptyStateMessage)
                    .font(DSTypography.body)
                    .foregroundStyle(DSColor.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(DSSpacing.large)
        }
    }

    private var resultsList: some View {
        GlassCard(padding: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(findings) { finding in
                        ScanResultRow(
                            systemImage: rowIcon(for: finding),
                            title: finding.item.category,
                            subtitle: finding.item.path,
                            sizeBytes: finding.item.sizeBytes,
                            safetyTier: finding.verdict.uiTier,
                            actionLabel: finding.verdict.isEligibleForQuarantine ? "Quarantine" : "Locked",
                            actionVariant: finding.verdict.isEligibleForQuarantine ? .secondary : .destructive
                        ) {
                            pendingQuarantine = [finding]
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
        isScanning = true
        defer { isScanning = false }
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

    private var pendingQuarantineBinding: Binding<QuarantineBatch?> {
        Binding(
            get: { pendingQuarantine.map(QuarantineBatch.init) },
            set: { pendingQuarantine = $0?.findings }
        )
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
}
