import SwiftUI
import UIDesignSystem

/// Landing screen: aggregate figures across every registered detector,
/// pulled from the same `AppEnvironment.scanSnapshotStore` snapshot every
/// other section reads — the Dashboard never runs its own separate scan
/// logic.
@available(macOS 26.0, *)
struct DashboardView: View {
    @Environment(AppEnvironment.self) private var environment

    @State private var findingsCount = 0
    @State private var totalReclaimableBytes: Int64 = 0
    @State private var quarantineCount = 0
    @State private var lastScanFinishedAt: Date?
    @State private var isScanning = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.large) {
                Text("MClean Pro")
                    .font(DSTypography.largeTitle)

                GlassControlGroup {
                    Button("Scan Everything", systemImage: "sparkle.magnifyingglass") {
                        Task { await scanNow() }
                    }
                    .dsButtonStyle(.primary)
                    .disabled(isScanning)

                    if isScanning {
                        ProgressView().controlSize(.small).padding(.leading, DSSpacing.xSmall)
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: DSSpacing.medium)], spacing: DSSpacing.medium) {
                    statCard(title: "Findings", value: "\(findingsCount)", systemImage: "magnifyingglass", tint: DSColor.accent)
                    statCard(title: "Reclaimable", value: ScanResultRow.formattedSize(totalReclaimableBytes), systemImage: "internaldrive", tint: DSColor.safe)
                    statCard(title: "In Quarantine", value: "\(quarantineCount)", systemImage: "xmark.bin", tint: DSColor.warning)
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: DSSpacing.xSmall) {
                        Text("Last Scan").font(DSTypography.heading)
                        Text(lastScanFinishedAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Never — run a scan to see findings across every module.")
                            .font(DSTypography.subheading)
                            .foregroundStyle(DSColor.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text("Build flavor: \(environment.capabilities.flavor.rawValue)")
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColor.textTertiary)
            }
            .padding(DSSpacing.xLarge)
        }
        .task { await refresh() }
    }

    private func statCard(title: String, value: String, systemImage: String, tint: Color) -> some View {
        GlassCard(tint: tint.opacity(0.18)) {
            VStack(alignment: .leading, spacing: DSSpacing.xSmall) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(tint)
                Text(value)
                    .font(DSTypography.title)
                Text(title)
                    .font(DSTypography.subheading)
                    .foregroundStyle(DSColor.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func refresh() async {
        let snapshot = await environment.scanSnapshotStore.currentSnapshot()
        findingsCount = snapshot.findings.count
        totalReclaimableBytes = snapshot.findings.reduce(Int64(0)) { $0 + ($1.item.sizeBytes ?? 0) }
        lastScanFinishedAt = snapshot.lastScanFinishedAt
        quarantineCount = (try? await environment.quarantineManager.listActive().count) ?? 0
    }

    private func scanNow() async {
        isScanning = true
        defer { isScanning = false }
        await environment.runFullScan()
        await refresh()
    }
}
