import SwiftUI

/// Mirrors the three tiers of `SafetyRules.SafetyVerdict`, for UI
/// presentation only.
///
/// `UIDesignSystem` has no dependency on `SafetyRules` (see `Package.swift`
/// — this package has no external SPM dependencies), so this enum is
/// intentionally a local, minimal duplicate rather than an import. **Keep
/// the three case names in sync by hand with `SafetyRules.SafetyVerdict`**
/// (`forbidden`, `safeAuto`, `needsConfirmation`); callers are expected to
/// map their real `SafetyVerdict` to this type at the UI boundary, e.g.:
///
/// ```swift
/// switch verdict {
/// case .forbidden: DSSafetyTier.forbidden
/// case .safeAuto: DSSafetyTier.safeAuto
/// case .needsConfirmation: DSSafetyTier.needsConfirmation
/// }
/// ```
public enum DSSafetyTier: Sendable, Hashable, CaseIterable {
    /// Matches the hardcoded denylist — never offered for deletion, full
    /// stop. Rendered as the most severe, unmistakable badge.
    case forbidden
    /// Matches a versioned rule marked safe for unattended cleanup.
    case safeAuto
    /// Requires explicit, per-item (or reviewed per-batch) confirmation.
    case needsConfirmation

    public var label: String {
        switch self {
        case .forbidden: "Never Delete"
        case .safeAuto: "Safe to Auto-Clean"
        case .needsConfirmation: "Needs Confirmation"
        }
    }

    public var systemImage: String {
        switch self {
        case .forbidden: "lock.shield.fill"
        case .safeAuto: "checkmark.seal.fill"
        case .needsConfirmation: "exclamationmark.triangle.fill"
        }
    }

    /// The tint applied to the badge's glass background.
    public var tintColor: Color {
        switch self {
        case .forbidden: DSColor.destructive
        case .safeAuto: DSColor.safe
        case .needsConfirmation: DSColor.warning
        }
    }
}

/// A compact badge that visually communicates a `DSSafetyTier` at a glance —
/// used next to every scan result row and anywhere a destructive action is
/// offered.
@available(macOS 26.0, *)
public struct SafetyBadge: View {
    private let tier: DSSafetyTier

    public init(_ tier: DSSafetyTier) {
        self.tier = tier
    }

    public var body: some View {
        Label(tier.label, systemImage: tier.systemImage)
            .labelStyle(.titleAndIcon)
            .font(DSTypography.captionStrong)
            .foregroundStyle(.white)
            .padding(.horizontal, DSSpacing.small)
            .padding(.vertical, DSSpacing.xxSmall)
            .glassEffect(.regular.tint(tier.tintColor), in: .capsule)
            .accessibilityLabel(Text(tier.label))
    }
}

@available(macOS 26.0, *)
#Preview("Safety Badges") {
    ZStack {
        DSColor.background.ignoresSafeArea()

        VStack(alignment: .leading, spacing: DSSpacing.medium) {
            ForEach(DSSafetyTier.allCases, id: \.self) { tier in
                SafetyBadge(tier)
            }
        }
        .padding(DSSpacing.xLarge)
    }
    .frame(width: 320, height: 220)
}
