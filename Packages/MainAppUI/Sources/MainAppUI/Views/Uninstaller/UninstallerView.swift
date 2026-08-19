import CoreScanEngine
import PowerUserInspectors
import RemoteControlServer
import SwiftUI
import UIDesignSystem

/// Per-app uninstall flow: pick an installed app, preview every related
/// file `Uninstaller.UninstallerService` found for it, then confirm —
/// reusing the exact same `QuarantineConfirmationSheet` ->
/// `FileSystemQuarantineManager` flow every other section in this app uses.
/// `UninstallerService` is a plain on-demand service, not part of the
/// routine scan pipeline — see `AppEnvironment.uninstallerService`'s doc
/// comment.
@available(macOS 26.0, *)
struct UninstallerView: View {
    @Environment(AppEnvironment.self) private var environment

    @State private var apps: [InstalledApp] = []
    @State private var isLoadingApps = true
    @State private var selectedApp: InstalledApp?
    @State private var relatedFindings: [ScanFinding] = []
    @State private var pendingQuarantine: [ScanFinding]?
    @State private var isQuarantining = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.large) {
            Label("Uninstaller", systemImage: "minus.app")
                .font(DSTypography.largeTitle)

            if let selectedApp {
                previewCard(for: selectedApp)
            } else {
                appPickerCard
            }
        }
        .padding(DSSpacing.xLarge)
        .task { await loadApps() }
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

    // MARK: - App picker

    private var appPickerCard: some View {
        GlassCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Choose an app to uninstall")
                    .font(DSTypography.heading)
                    .padding(DSSpacing.medium)

                if isLoadingApps {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Finding installed apps…").font(DSTypography.subheading).foregroundStyle(DSColor.textSecondary)
                    }
                    .padding(DSSpacing.medium)
                } else if apps.isEmpty {
                    Text("No apps found under /Applications or ~/Applications.")
                        .font(DSTypography.subheading)
                        .foregroundStyle(DSColor.textSecondary)
                        .padding(DSSpacing.medium)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(apps) { app in
                                ScanResultRow(
                                    systemImage: "app.dashed",
                                    title: app.name,
                                    subtitle: app.bundleIdentifier ?? app.path,
                                    sizeBytes: app.sizeBytes,
                                    safetyTier: nil,
                                    actionLabel: "Preview",
                                    actionVariant: .secondary
                                ) {
                                    selectApp(app)
                                }
                                if app.id != apps.last?.id {
                                    Divider().opacity(0.3)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 420)
                }
            }
        }
    }

    // MARK: - Related-files preview

    private func previewCard(for app: InstalledApp) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.medium) {
            HStack {
                Text(app.name).font(DSTypography.heading)
                Spacer()
                Button("Choose a different app", systemImage: "chevron.left") {
                    selectedApp = nil
                    relatedFindings = []
                }
                .dsButtonStyle(.secondary)
            }

            Text("\(relatedFindings.count) related file\(relatedFindings.count == 1 ? "" : "s") found. Nothing is removed until you confirm below.")
                .font(DSTypography.subheading)
                .foregroundStyle(DSColor.textSecondary)

            GlassCard(padding: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(relatedFindings) { finding in
                            ScanResultRow(
                                systemImage: rowIcon(for: finding),
                                title: finding.item.category,
                                subtitle: finding.item.path,
                                sizeBytes: finding.item.sizeBytes,
                                safetyTier: finding.verdict.uiTier,
                                actionLabel: finding.verdict.isEligibleForQuarantine ? "Remove" : "Locked",
                                actionVariant: finding.verdict.isEligibleForQuarantine ? .secondary : .destructive
                            ) {
                                pendingQuarantine = [finding]
                            }
                            .disabled(!finding.verdict.isEligibleForQuarantine)
                            if finding.id != relatedFindings.last?.id {
                                Divider().opacity(0.3)
                            }
                        }
                    }
                }
                .frame(maxHeight: 360)
            }

            HStack {
                Spacer()
                Button("Uninstall (\(eligibleFindings.count) items)", systemImage: "trash") {
                    pendingQuarantine = eligibleFindings
                }
                .dsButtonStyle(.destructive)
                .disabled(eligibleFindings.isEmpty)
            }
        }
    }

    private var eligibleFindings: [ScanFinding] {
        relatedFindings.filter { $0.verdict.isEligibleForQuarantine }
    }

    private func rowIcon(for finding: ScanFinding) -> String {
        switch finding.verdict {
        case .forbidden: "lock.shield.fill"
        case .safeAuto: "checkmark.seal"
        case .needsConfirmation: "exclamationmark.triangle"
        }
    }

    // MARK: - Actions

    private func loadApps() async {
        isLoadingApps = true
        apps = await environment.installedAppsInspector.scanApplications()
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        isLoadingApps = false
    }

    private func selectApp(_ app: InstalledApp) {
        selectedApp = app
        let items = environment.uninstallerService.relatedFiles(for: app)
        relatedFindings = items.map { ScanFinding(item: $0, verdict: environment.safetyClassifier.classify($0)) }
    }

    private func performQuarantine(_ batch: [ScanFinding]) async {
        isQuarantining = true
        defer { isQuarantining = false }

        var failures: [String] = []
        var quarantinedIDs: Set<UUID> = []
        for finding in batch {
            do {
                _ = try await environment.quarantineManager.quarantine(finding.item, retention: .default)
                quarantinedIDs.insert(finding.id)
            } catch {
                failures.append("\(finding.item.path): \(error)")
            }
        }

        relatedFindings.removeAll { quarantinedIDs.contains($0.id) }
        pendingQuarantine = nil
        if !failures.isEmpty {
            errorMessage = failures.joined(separator: "\n")
        }
    }

    // MARK: - Sheet plumbing

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
