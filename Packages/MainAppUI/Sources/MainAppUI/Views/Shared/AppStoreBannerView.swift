import SwiftUI
import UIDesignSystem

/// Persistent, honest banner shown only in the App Store build flavor,
/// explaining the sandbox limitation and linking to the Developer ID
/// version — per PROMPT MASTER §5.8. Never hidden/dismissed permanently:
/// it reappears every launch, since the limitation it describes is
/// permanent for as long as the user runs the App Store build.
@available(macOS 26.0, *)
struct AppStoreBannerView: View {
    /// Placeholder — no real marketing site exists yet. Documented here
    /// rather than silently hardcoded so it's easy to find and replace.
    private static let developerIDDownloadURL = URL(string: "https://mcleanpro.app/download")!

    var body: some View {
        GlassCard(tint: DSColor.accent.opacity(0.15)) {
            HStack(alignment: .top, spacing: DSSpacing.medium) {
                Image(systemName: "shippingbox.and.arrow.backward")
                    .font(.title2)
                    .foregroundStyle(DSColor.accent)

                VStack(alignment: .leading, spacing: DSSpacing.xSmall) {
                    Text("You're using the App Store version")
                        .font(DSTypography.heading)
                    Text(
                        "For your safety, App Store apps run in a sandbox: MClean Pro can "
                        + "only see files you explicitly pick, and can't run the LAN Remote "
                        + "Control server or the privileged helper some deep-clean features "
                        + "need. The Developer ID version has full functionality and is "
                        + "notarized by Apple outside the App Store."
                    )
                    .font(DSTypography.subheading)
                    .foregroundStyle(DSColor.textSecondary)

                    Link(destination: Self.developerIDDownloadURL) {
                        Label("Get the Developer ID version", systemImage: "arrow.down.circle")
                    }
                    .font(DSTypography.subheading)
                    .padding(.top, DSSpacing.xxSmall)
                }

                Spacer(minLength: 0)
            }
        }
    }
}
