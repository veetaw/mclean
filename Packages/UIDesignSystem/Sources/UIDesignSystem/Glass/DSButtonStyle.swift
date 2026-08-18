import SwiftUI

/// Semantic intent for a glass button. Maps to the system `.glass` /
/// `.glassProminent` button styles with sane, app-wide defaults so feature
/// modules don't each reinvent tint/weight/shape choices.
public enum DSButtonVariant: Sendable, Hashable {
    /// The single primary action in a given context (e.g. "Clean Now").
    /// There should be at most one prominent action visible at a time —
    /// see the Liquid Glass HIG guidance on tinting multiple controls.
    case primary
    /// A supporting/alternate action. The common default for most buttons.
    case secondary
    /// A destructive, hard-to-reverse action (e.g. "Delete Permanently",
    /// "Empty Quarantine"). Deliberately styled to look distinct and
    /// serious — this app's destructive actions matter for safety UX, and
    /// should never look like a routine secondary action.
    case destructive
}

/// Applies `DSButtonVariant`'s look to a `Button`, built on top of the
/// system `.glass`/`.glassProminent` button styles (never a raw
/// `.glassEffect` placed behind a button — see the `apple-liquid-glass`
/// skill).
@available(macOS 26.0, *)
private struct DSGlassButtonModifier: ViewModifier {
    let variant: DSButtonVariant

    func body(content: Content) -> some View {
        switch variant {
        case .primary:
            content
                .buttonStyle(.glassProminent)
                .tint(DSColor.accent)
                .buttonBorderShape(.capsule)
        case .secondary:
            content
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
        case .destructive:
            content
                .buttonStyle(.glassProminent)
                .tint(DSColor.destructive)
                .buttonBorderShape(.capsule)
                .fontWeight(.semibold)
        }
    }
}

@available(macOS 26.0, *)
public extension View {
    /// Applies MClean Pro's standard glass button treatment for the given
    /// semantic variant. Prefer this over calling `.buttonStyle(.glass)` /
    /// `.glassProminent` directly so destructive actions stay visually
    /// consistent app-wide.
    func dsButtonStyle(_ variant: DSButtonVariant) -> some View {
        modifier(DSGlassButtonModifier(variant: variant))
    }
}

@available(macOS 26.0, *)
#Preview("Glass Button Variants") {
    ZStack {
        LinearGradient(colors: [.mint, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea()

        GlassEffectContainer(spacing: DSSpacing.small) {
            HStack(spacing: DSSpacing.small) {
                Button("Secondary") {}.dsButtonStyle(.secondary)
                Button("Primary") {}.dsButtonStyle(.primary)
                Button("Delete Forever") {}.dsButtonStyle(.destructive)
            }
        }
        .padding(DSSpacing.xLarge)
    }
    .frame(width: 480, height: 200)
}
