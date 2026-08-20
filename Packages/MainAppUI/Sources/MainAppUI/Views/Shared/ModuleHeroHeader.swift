import SwiftUI
import UIDesignSystem

/// A round, tinted glass tile behind an SF Symbol — the small "icon badge"
/// every module's hero header uses to give its landing screen more visual
/// weight than a bare `Label`. Inspired by CleanMyMac X's big per-module
/// icon treatment (LAYOUT only, per this phase's brief — the tint still
/// comes from `DSColor`'s existing tokens, never a new palette).
@available(macOS 26.0, *)
struct ModuleIconBadge: View {
    let systemImage: String
    let tint: Color
    var size: CGFloat = 52

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .dsGlassCard(cornerRadius: DSCornerRadius.large, padding: 0, tint: tint.opacity(0.16))
    }
}

/// Shared "hero" header for a top-level module landing screen: an icon
/// badge, a large title, an optional status subtitle, and an optional
/// trailing accessory (typically a `GlassControlGroup` of the module's
/// primary actions, e.g. Rescan / Clean).
///
/// Deliberately lives in `MainAppUI`, not `UIDesignSystem` — it speaks this
/// app's vocabulary (a "module landing screen" isn't a generic Liquid Glass
/// concept), the same layering `ScanItemRowDisplay`/`AppBundleDisplayCache`
/// already use elsewhere in this module: `UIDesignSystem` stays generic
/// primitives (`GlassCard`, tokens, button styles); feature-specific
/// composition happens here, one level up.
@available(macOS 26.0, *)
struct ModuleHeroHeader<Accessory: View>: View {
    let title: String
    let systemImage: String
    var subtitle: String?
    var tint: Color = DSColor.accent
    @ViewBuilder var accessory: () -> Accessory

    init(
        title: String,
        systemImage: String,
        subtitle: String? = nil,
        tint: Color = DSColor.accent,
        @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() }
    ) {
        self.title = title
        self.systemImage = systemImage
        self.subtitle = subtitle
        self.tint = tint
        self.accessory = accessory
    }

    var body: some View {
        HStack(alignment: .top, spacing: DSSpacing.medium) {
            ModuleIconBadge(systemImage: systemImage, tint: tint)

            VStack(alignment: .leading, spacing: DSSpacing.xxSmall) {
                Text(title)
                    .font(DSTypography.largeTitle)
                if let subtitle {
                    Text(subtitle)
                        .font(DSTypography.subheading)
                        .foregroundStyle(DSColor.textSecondary)
                }
            }

            Spacer(minLength: DSSpacing.small)

            accessory()
        }
    }
}

/// Shared empty-state card: icon, short headline, short explanatory
/// subtext, and an optional primary action button — replaces the
/// "just a bare `Text`" empty states this phase's brief specifically calls
/// out as too plain. Lives alongside `ModuleHeroHeader` for the same
/// layering reason (see its doc comment).
@available(macOS 26.0, *)
struct ModuleEmptyStateCard: View {
    let systemImage: String
    let headline: String
    let message: String
    var tint: Color = DSColor.safe
    var actionLabel: String?
    var actionSystemImage: String?
    var isActionDisabled: Bool = false
    var action: (() -> Void)?

    var body: some View {
        GlassCard {
            VStack(spacing: DSSpacing.small) {
                Image(systemName: systemImage)
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(tint)
                Text(headline)
                    .font(DSTypography.title)
                Text(message)
                    .font(DSTypography.subheading)
                    .foregroundStyle(DSColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let actionLabel, let action {
                    Button(actionLabel, systemImage: actionSystemImage ?? "arrow.clockwise", action: action)
                        .dsButtonStyle(.primary)
                        .disabled(isActionDisabled)
                        .padding(.top, DSSpacing.xxSmall)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DSSpacing.medium)
        }
    }
}

#if DEBUG
@available(macOS 26.0, *)
#Preview("Module Hero + Empty State") {
    ZStack {
        DSColor.background.ignoresSafeArea()
        VStack(alignment: .leading, spacing: DSSpacing.large) {
            ModuleHeroHeader(
                title: "System Junk",
                systemImage: "trash",
                subtitle: "Last scan: today · 3.2 GB reclaimable across 214 items"
            ) {
                GlassControlGroup {
                    Button("Rescan", systemImage: "arrow.clockwise") {}.dsButtonStyle(.secondary)
                }
            }
            ModuleEmptyStateCard(
                systemImage: "checkmark.seal",
                headline: "All Clear",
                message: "No junk found yet. Rescan to check Trash, large/old files, duplicates, and caches.",
                actionLabel: "Rescan Now",
                actionSystemImage: "arrow.clockwise"
            ) {}
        }
        .padding(DSSpacing.xLarge)
    }
    .frame(width: 640, height: 420)
}
#endif
