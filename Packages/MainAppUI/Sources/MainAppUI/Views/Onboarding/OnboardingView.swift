import PowerUserInspectors
import SwiftUI
import UIDesignSystem

/// First-run explanation sequence, shown *before* any permission prompt —
/// each step explains *why* MClean Pro wants a permission and opens the
/// relevant System Settings pane (via `TCCSettingsPaneOpener`, the same
/// type `PowerUserInspectors` uses — macOS has no API for a third-party
/// app to request Full Disk Access/Accessibility/Local Network
/// programmatically the way it does camera/microphone, so "open the right
/// System Settings pane" is the correct, only mechanism here).
///
/// Every step has a "Skip for now" path, and the sheet can always be
/// dismissed — the app never gates launch or basic functionality on
/// completing this flow or on any permission actually being granted.
/// Declining just means some sections show reduced functionality (already
/// handled independently by each feature view — e.g. `TCCDatabaseReader`
/// degrades to `.unavailable(reason: .fullDiskAccessRequired)` rather than
/// crashing).
@available(macOS 26.0, *)
struct OnboardingView: View {
    let environment: AppEnvironment
    let onFinished: () -> Void

    @State private var stepIndex = 0

    private var steps: [OnboardingStep] {
        var steps: [OnboardingStep] = [.welcome]
        steps.append(.fullDiskAccess)
        if environment.capabilities.canRunRemoteControlServer {
            steps.append(.localNetwork)
        }
        if environment.capabilities.canInstallPrivilegedHelper {
            steps.append(.accessibility)
        }
        steps.append(.done)
        return steps
    }

    var body: some View {
        VStack(spacing: DSSpacing.large) {
            content(for: steps[stepIndex])
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

            HStack {
                Button("Skip for Now") {
                    onFinished()
                }
                .dsButtonStyle(.secondary)

                Spacer()

                Text("\(stepIndex + 1) of \(steps.count)")
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColor.textTertiary)

                Spacer()

                Button(stepIndex == steps.count - 1 ? "Get Started" : "Continue") {
                    if stepIndex == steps.count - 1 {
                        onFinished()
                    } else {
                        stepIndex += 1
                    }
                }
                .dsButtonStyle(.primary)
            }
        }
        .padding(DSSpacing.xLarge)
        .frame(width: 560, height: 420)
    }

    @ViewBuilder
    private func content(for step: OnboardingStep) -> some View {
        VStack(spacing: DSSpacing.large) {
            Image(systemName: step.systemImage)
                .font(.system(size: 48))
                .foregroundStyle(DSColor.accent)

            Text(step.title)
                .font(DSTypography.largeTitle)
                .multilineTextAlignment(.center)

            Text(step.explanation)
                .font(DSTypography.body)
                .foregroundStyle(DSColor.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)

            if let service = step.tccService {
                Button("Open System Settings", systemImage: "arrow.up.right.square") {
                    environment.tccSettingsPaneOpener.openSettingsPane(for: service)
                }
                .dsButtonStyle(.secondary)
            }

            if step == .welcome {
                Text("You can always change these later from Settings, and MClean Pro stays fully usable — with reduced functionality in some sections — if you decline any of them.")
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColor.textTertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }
        }
    }
}

private enum OnboardingStep: Hashable {
    case welcome
    case fullDiskAccess
    case localNetwork
    case accessibility
    case done

    var title: String {
        switch self {
        case .welcome: "Welcome to MClean Pro"
        case .fullDiskAccess: "Full Disk Access"
        case .localNetwork: "Local Network Access"
        case .accessibility: "Accessibility"
        case .done: "You're All Set"
        }
    }

    var systemImage: String {
        switch self {
        case .welcome: "sparkles"
        case .fullDiskAccess: "internaldrive"
        case .localNetwork: "wifi"
        case .accessibility: "figure.wave"
        case .done: "checkmark.circle"
        }
    }

    var explanation: String {
        switch self {
        case .welcome:
            "A quick tour before we ask for anything. MClean Pro finds developer-tool caches, mobile-toolchain artifacts, and system clutter you can safely reclaim — everything goes through a reversible quarantine, never an instant delete."
        case .fullDiskAccess:
            "Full Disk Access lets MClean Pro read cache/build directories under other apps' containers and inspect Privacy permissions (TCC) for the Power User section. Without it, some findings will be incomplete rather than wrong — nothing breaks."
        case .localNetwork:
            "Local Network access lets the Remote Control feature advertise itself to a paired phone/tablet on your Wi-Fi so you can review findings and approve cleanup away from your Mac. It's entirely optional and off until you start it from the Remote Control tab."
        case .accessibility:
            "Some Power User maintenance actions (offered later, gated behind the privileged helper) need Accessibility to interact with system dialogs safely. Only Developer ID builds ever request this — the App Store build never does."
        case .done:
            "Explore the sidebar: Dashboard for an overview, Developer Tools / Mobile Dev / Power User for real findings, and Quarantine to review or restore anything MClean Pro has set aside."
        }
    }

    /// `TCCSettingsPaneOpener` has no specific anchor mapping for Local
    /// Network (it's not in `TCCServiceIdentifier`'s well-known constants),
    /// so this intentionally uses an identifier `settingsURL(for:)` doesn't
    /// recognize — that type's own documented behavior is to fall back to
    /// `generalPrivacySettingsURL` for an unmapped service, which is the
    /// best-effort outcome we want here too.
    var tccService: TCCServiceIdentifier? {
        switch self {
        case .fullDiskAccess: .fullDiskAccess
        case .accessibility: .accessibility
        case .localNetwork: TCCServiceIdentifier(rawValue: "kTCCServiceNetworkLocal")
        case .welcome, .done: nil
        }
    }
}
