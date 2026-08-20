import RemoteControlServer
import SwiftUI
import UIDesignSystem

/// Confirmation sheet shown before **any** quarantine action, including a
/// batch of `safeAuto`-verdict items — per the hard constraint that nothing
/// ever moves to quarantine from a silent one-tap action. Always lists what
/// is about to happen (every item, its path, its size, its verdict) before
/// the user can confirm.
@available(macOS 26.0, *)
struct QuarantineConfirmationSheet: View {
    let findings: [ScanFinding]
    let isWorking: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private var totalBytes: Int64 {
        findings.reduce(Int64(0)) { $0 + ($1.item.sizeBytes ?? 0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.medium) {
            VStack(alignment: .leading, spacing: DSSpacing.xxSmall) {
                Text("Move to Quarantine?")
                    .font(DSTypography.title)
                Text(
                    "\(findings.count) item\(findings.count == 1 ? "" : "s") "
                    + "(\(ScanResultRow.formattedSize(totalBytes))) will be moved to a reversible "
                    + "quarantine folder, not deleted. You can restore anything from the "
                    + "Quarantine tab within its retention window."
                )
                .font(DSTypography.subheading)
                .foregroundStyle(DSColor.textSecondary)
            }

            GlassCard {
                // `LazyVStack` — see the identical note on
                // `FindingsListView.resultsList`. A "Clean Safe Items" batch
                // can be every `safeAuto` finding from a full scan, so this
                // list is exactly as susceptible to the eager-`VStack`
                // virtualization trap as the main findings list is.
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(findings) { finding in
                            VStack(alignment: .leading, spacing: DSSpacing.xxSmall) {
                                HStack {
                                    // Same `.app`-bundle name resolution as
                                    // `ScanResultRow` call sites — see
                                    // `ScanItemRowDisplay`.
                                    Text(ScanItemRowDisplay.title(for: finding.item))
                                        .font(DSTypography.heading)
                                    Spacer()
                                    SafetyBadge(finding.verdict.uiTier)
                                }
                                Text(finding.item.path)
                                    .font(DSTypography.caption)
                                    .foregroundStyle(DSColor.textSecondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .padding(.vertical, DSSpacing.xSmall)

                            if finding.id != findings.last?.id {
                                Divider().opacity(0.3)
                            }
                        }
                    }
                }
                .frame(maxHeight: 260)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .dsButtonStyle(.secondary)
                    .disabled(isWorking)
                Button(isWorking ? "Moving…" : "Move to Quarantine", action: onConfirm)
                    .dsButtonStyle(.primary)
                    .disabled(isWorking || findings.isEmpty)
            }
        }
        .padding(DSSpacing.xLarge)
        .frame(width: 520)
    }
}
