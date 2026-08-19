import PowerUserInspectors
import SwiftUI
import UIDesignSystem
import VirusTotalClient

@available(macOS 26.0, *)
struct SettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var retentionDays = 7

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.large) {
                Label("Settings", systemImage: "gearshape")
                    .font(DSTypography.largeTitle)

                buildInfoCard
                quarantineCard
                permissionsCard
                virusTotalCard
            }
            .padding(DSSpacing.xLarge)
        }
    }

    private var buildInfoCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: DSSpacing.xSmall) {
                Text("Build").font(DSTypography.heading)
                LabeledContent("Flavor", value: environment.capabilities.flavor.rawValue)
                LabeledContent("Privileged helper", value: environment.capabilities.canInstallPrivilegedHelper ? "Available" : "Not available (sandboxed)")
                LabeledContent("Remote Control server", value: environment.capabilities.canRunRemoteControlServer ? "Available" : "Not available (sandboxed)")
                LabeledContent("Full-disk / other-user scanning", value: environment.capabilities.canAccessOtherUsersFiles ? "Available" : "User-selected files only")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var quarantineCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: DSSpacing.small) {
                Text("Quarantine").font(DSTypography.heading)
                Text("Default retention before an item becomes eligible for permanent deletion. Changing this only affects items quarantined after the change.")
                    .font(DSTypography.subheading)
                    .foregroundStyle(DSColor.textSecondary)
                Stepper("Retention: \(retentionDays) day\(retentionDays == 1 ? "" : "s")", value: $retentionDays, in: 1...30)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var permissionsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: DSSpacing.small) {
                Text("Permissions").font(DSTypography.heading)
                Text("MClean Pro never changes a permission grant on your behalf — macOS doesn't allow that. These buttons open the exact System Settings pane so you can review or change it yourself.")
                    .font(DSTypography.subheading)
                    .foregroundStyle(DSColor.textSecondary)

                permissionRow(title: "Full Disk Access", service: .fullDiskAccess)
                if environment.capabilities.canInstallPrivilegedHelper {
                    permissionRow(title: "Accessibility", service: .accessibility)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func permissionRow(title: String, service: TCCServiceIdentifier) -> some View {
        HStack {
            Text(title).font(DSTypography.body)
            Spacer()
            Button("Open Settings", systemImage: "arrow.up.right.square") {
                environment.tccSettingsPaneOpener.openSettingsPane(for: service)
            }
            .dsButtonStyle(.secondary)
            .controlSize(.small)
        }
    }

    private var virusTotalCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: DSSpacing.small) {
                Text("VirusTotal Hash Check").font(DSTypography.heading)
                if environment.virusTotalClient?.isConfigured == true {
                    Text("Configured.")
                        .font(DSTypography.subheading)
                        .foregroundStyle(DSColor.safe)
                } else {
                    Text("Not configured yet — no VirusTotalClient implementation is wired in this build (the package only defines the protocol so far). Hash-check lookups will show as unavailable everywhere in the UI until an API key is set here, never hidden entirely.")
                        .font(DSTypography.subheading)
                        .foregroundStyle(DSColor.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
