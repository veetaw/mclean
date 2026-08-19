import RemoteControlServer
import SwiftUI
import UIDesignSystem

/// Pairing status + start/stop toggle for `RemoteControlServer`. Only ever
/// reachable when `Capabilities.canRunRemoteControlServer` is `true` —
/// `ContentView` filters this section out of the sidebar entirely
/// otherwise (a sandboxed App Store build can't run the LAN listener), but
/// this view also degrades gracefully (rather than crashing) if it's ever
/// shown with `environment.remoteControlServer == nil`.
@available(macOS 26.0, *)
struct RemoteControlView: View {
    @Environment(AppEnvironment.self) private var environment

    @State private var isRunning = false
    @State private var boundPort: UInt16?
    @State private var pairedDevices: [PairedDevice] = []
    @State private var activeInvitation: PairingInvitation?
    @State private var allowMobileApprovalFulfillment = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.large) {
            Label("Remote Control", systemImage: "wifi")
                .font(DSTypography.largeTitle)

            if let server = environment.remoteControlServer {
                statusCard(server: server)
                pairingCard(server: server)
                devicesCard(server: server)
                settingsCard(server: server)
            } else {
                unavailableCard
            }
        }
        .padding(DSSpacing.xLarge)
        .task { await refresh() }
        .alert("Couldn't complete that action", isPresented: errorAlertBinding) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var unavailableCard: some View {
        GlassCard(tint: DSColor.warning.opacity(0.18)) {
            Text("Remote Control isn't available in this build.")
                .font(DSTypography.body)
                .foregroundStyle(DSColor.textSecondary)
        }
    }

    private func statusCard(server: RemoteControlServer) -> some View {
        GlassCard {
            HStack {
                VStack(alignment: .leading, spacing: DSSpacing.xxSmall) {
                    Text(isRunning ? "Running" : "Stopped")
                        .font(DSTypography.heading)
                    if isRunning, let boundPort {
                        Text("Listening on port \(boundPort), LAN-only. Every connection is checked against the real TCP peer address.")
                            .font(DSTypography.subheading)
                            .foregroundStyle(DSColor.textSecondary)
                    } else {
                        Text("Start the server to let a paired phone/tablet on your LAN view findings and request quarantine approvals.")
                            .font(DSTypography.subheading)
                            .foregroundStyle(DSColor.textSecondary)
                    }
                }
                Spacer()
                Button(isRunning ? "Stop" : "Start", systemImage: isRunning ? "stop.circle" : "play.circle") {
                    Task { await toggleServer(server: server) }
                }
                .dsButtonStyle(isRunning ? .destructive : .primary)
            }
        }
    }

    private func pairingCard(server: RemoteControlServer) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: DSSpacing.small) {
                Text("Pair a Device").font(DSTypography.heading)

                if let activeInvitation {
                    VStack(alignment: .leading, spacing: DSSpacing.xxSmall) {
                        Text("Pairing token (expires \(activeInvitation.expiresAt.formatted(date: .omitted, time: .shortened))):")
                            .font(DSTypography.subheading)
                            .foregroundStyle(DSColor.textSecondary)
                        Text(activeInvitation.token)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                        Text("Rendering this as a scannable QR code is a follow-up — the mobile web app also accepts typing this token in directly. See RemoteWebApp/README.md.")
                            .font(DSTypography.caption)
                            .foregroundStyle(DSColor.textTertiary)
                    }
                } else {
                    Text("Generate a one-time pairing token to connect a new device.")
                        .font(DSTypography.subheading)
                        .foregroundStyle(DSColor.textSecondary)
                }

                Button("Generate Pairing Token", systemImage: "qrcode") {
                    Task { await beginPairing(server: server) }
                }
                .dsButtonStyle(.secondary)
                .disabled(!isRunning)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func devicesCard(server: RemoteControlServer) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: DSSpacing.small) {
                Text("Paired Devices").font(DSTypography.heading)
                if pairedDevices.isEmpty {
                    Text("No devices paired yet.")
                        .font(DSTypography.subheading)
                        .foregroundStyle(DSColor.textSecondary)
                } else {
                    ForEach(pairedDevices) { device in
                        HStack {
                            VStack(alignment: .leading, spacing: DSSpacing.xxSmall) {
                                Text(device.displayName).font(DSTypography.body)
                                Text("Paired \(device.pairedAt.formatted(date: .abbreviated, time: .shortened))\(device.isActive ? "" : " · revoked")")
                                    .font(DSTypography.caption)
                                    .foregroundStyle(DSColor.textSecondary)
                            }
                            Spacer()
                            if device.isActive {
                                Button("Revoke", role: .destructive) {
                                    Task {
                                        await server.revokeDevice(device.id)
                                        await refresh()
                                    }
                                }
                                .dsButtonStyle(.destructive)
                                .controlSize(.small)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func settingsCard(server: RemoteControlServer) -> some View {
        GlassCard {
            Toggle(isOn: Binding(
                get: { allowMobileApprovalFulfillment },
                set: { newValue in
                    allowMobileApprovalFulfillment = newValue
                    var settings = server.settings
                    settings.allowMobileApprovalFulfillment = newValue
                    server.updateSettings(settings)
                }
            )) {
                VStack(alignment: .leading, spacing: DSSpacing.xxSmall) {
                    Text("Allow paired devices to approve quarantine remotely")
                        .font(DSTypography.body)
                    Text("Off by default. When off, a paired device can only *request* quarantine — a human still confirms from this Mac.")
                        .font(DSTypography.caption)
                        .foregroundStyle(DSColor.textSecondary)
                }
            }
            .toggleStyle(.switch)
        }
    }

    // MARK: - Actions

    private func refresh() async {
        guard let server = environment.remoteControlServer else { return }
        isRunning = server.isRunning
        boundPort = try? UInt16(server.boundPort())
        pairedDevices = await server.pairedDevices()
        allowMobileApprovalFulfillment = server.settings.allowMobileApprovalFulfillment
    }

    private func toggleServer(server: RemoteControlServer) async {
        do {
            if isRunning {
                environment.stopRemoteControlServer()
            } else {
                _ = try environment.startRemoteControlServer()
            }
            await refresh()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func beginPairing(server: RemoteControlServer) async {
        activeInvitation = await server.beginPairing()
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
}
