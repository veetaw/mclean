import SwiftUI
import UIDesignSystem

/// PROMPT MASTER §5.1 describes a "System Junk / Large & Old Files" core
/// detector module (system caches, logs, trash, large-and-old files,
/// duplicates). **That module does not exist anywhere in this repository
/// yet** — `CoreScanEngine.DetectorCategory` reserves the cases
/// (`.systemJunk`, `.trash`, `.largeAndOldFiles`, `.duplicates`), but no
/// package implements them (only `DevToolsDetectors`, `MobileDevDetectors`,
/// and `PowerUserInspectors.InstalledAppsDetector` register real
/// detectors today).
///
/// Building that detector set is out of scope for `Agent:MainAppUI` (whose
/// job is assembling what already exists, not inventing a new detector
/// module) — this is a documented gap, not a silent omission. This view is
/// the honest placeholder for that gap: it explains what's missing rather
/// than showing an empty findings list that looks like "scanned, found
/// nothing."
@available(macOS 26.0, *)
struct SystemJunkPlaceholderView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.large) {
            Label("System Junk / Large & Old Files", systemImage: "trash")
                .font(DSTypography.largeTitle)

            GlassCard(tint: DSColor.warning.opacity(0.18)) {
                VStack(alignment: .leading, spacing: DSSpacing.small) {
                    Label("Not implemented yet", systemImage: "exclamationmark.triangle")
                        .font(DSTypography.heading)
                        .foregroundStyle(DSColor.warning)

                    Text(
                        "PROMPT MASTER §5.1 describes a core System Junk / Trash / "
                        + "Large & Old Files / Duplicates detector module. No package "
                        + "in this repository implements it yet — only Developer "
                        + "Tools, Mobile Dev, and Power User (installed apps) have "
                        + "real detectors today. This section is a placeholder so the "
                        + "gap is visible in the app itself, rather than silently "
                        + "missing from the sidebar."
                    )
                    .font(DSTypography.body)
                    .foregroundStyle(DSColor.textSecondary)

                    Text("Reserved categories already defined in CoreScanEngine.DetectorCategory: systemJunk, trash, largeAndOldFiles, duplicates.")
                        .font(DSTypography.caption)
                        .foregroundStyle(DSColor.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()
        }
        .padding(DSSpacing.xLarge)
    }
}
