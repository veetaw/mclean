import SafetyRules
import SwiftUI
import UIDesignSystem

/// Lists everything currently sitting in `FileSystemQuarantineManager`,
/// with restore + (for expired-retention items) purge actions. Every
/// destructive action here is still explicit and per-item/per-batch
/// confirmed — `purgeExpired()` in particular is never called implicitly,
/// matching `SAFETY_RULES.md`.
@available(macOS 26.0, *)
struct QuarantineView: View {
    @Environment(AppEnvironment.self) private var environment

    @State private var receipts: [QuarantineReceipt] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var pendingPurgeConfirmation = false
    @State private var isPurging = false

    private var expiredCount: Int {
        let now = Date()
        return receipts.filter { $0.purgeEligibleAt <= now }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.large) {
            ModuleHeroHeader(
                title: "Quarantine",
                systemImage: "xmark.bin",
                subtitle: "Items here were moved, not deleted. They're restorable until their retention window (default 7 days) elapses.",
                tint: DSColor.warning
            ) {
                GlassControlGroup {
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        Task { await refresh() }
                    }
                    .dsButtonStyle(.secondary)

                    if expiredCount > 0 {
                        Button("Purge Expired (\(expiredCount))", systemImage: "trash") {
                            pendingPurgeConfirmation = true
                        }
                        .dsButtonStyle(.destructive)
                    }
                }
            }

            if receipts.isEmpty {
                ModuleEmptyStateCard(
                    systemImage: "xmark.bin",
                    headline: "Quarantine Is Empty",
                    message: "Items you quarantine from other tabs will show up here until you restore them or their retention window elapses.",
                    tint: DSColor.textSecondary
                )
            } else {
                GlassCard(padding: 0) {
                    // `LazyVStack` — see the identical note on
                    // `FindingsListView.resultsList`; applies here too since
                    // this is the same `ScrollView` + eager-`VStack`
                    // non-virtualized pattern.
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(receipts) { receipt in
                                receiptRow(receipt)
                                if receipt.id != receipts.last?.id {
                                    Divider().opacity(0.3)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(DSSpacing.xLarge)
        .task { await refresh() }
        .alert("Permanently delete \(expiredCount) expired item(s)?", isPresented: $pendingPurgeConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Permanently", role: .destructive) {
                Task { await purgeExpired() }
            }
        } message: {
            Text("This cannot be undone. Only items whose retention window has already elapsed are affected.")
        }
        .alert("Couldn't complete that action", isPresented: errorAlertBinding) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func receiptRow(_ receipt: QuarantineReceipt) -> some View {
        HStack(spacing: DSSpacing.medium) {
            VStack(alignment: .leading, spacing: DSSpacing.xxSmall) {
                // For a quarantined `.app` bundle, show its resolved display
                // name instead of the generic detector `category` (e.g.
                // "Installed application") — same fix as `ScanResultRow`
                // call sites, applied here even though this row doesn't use
                // `ScanResultRow`. The bundle no longer exists at
                // `originalPath` once quarantined, so this falls back to the
                // filename-derived name (still readable) rather than reading
                // a now-missing `Info.plist`.
                Text(ScanItemRowDisplay.title(for: receipt.sourceItem))
                    .font(DSTypography.heading)
                Text(receipt.originalPath)
                    .font(DSTypography.subheading)
                    .foregroundStyle(DSColor.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(purgeEligibleText(for: receipt))
                    .font(DSTypography.caption)
                    .foregroundStyle(receipt.purgeEligibleAt <= Date() ? DSColor.warning : DSColor.textTertiary)
            }

            Spacer()

            if let sizeBytes = receipt.sourceItem.sizeBytes {
                Text(ScanResultRow.formattedSize(sizeBytes))
                    .font(DSTypography.caption.monospacedDigit())
                    .foregroundStyle(DSColor.textSecondary)
            }

            Button("Restore") {
                Task { await restore(receipt) }
            }
            .dsButtonStyle(.secondary)
            .controlSize(.small)
        }
        .padding(.vertical, DSSpacing.small)
        .padding(.horizontal, DSSpacing.medium)
    }

    private func purgeEligibleText(for receipt: QuarantineReceipt) -> String {
        if receipt.purgeEligibleAt <= Date() {
            return "Eligible for permanent deletion"
        }
        return "Purge-eligible \(receipt.purgeEligibleAt.formatted(date: .abbreviated, time: .omitted))"
    }

    private func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            receipts = try await environment.quarantineManager.listActive()
                .sorted { $0.quarantinedAt > $1.quarantinedAt }
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func restore(_ receipt: QuarantineReceipt) async {
        do {
            try await environment.quarantineManager.restore(receipt)
            await refresh()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func purgeExpired() async {
        isPurging = true
        defer { isPurging = false }
        do {
            _ = try await environment.quarantineManager.purgeExpired()
            await refresh()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
}
