import SwiftUI

/// A reusable glass card/panel — the base surface for grouped content
/// throughout the app (settings sections, scan summaries, onboarding
/// panels).
///
/// Wraps `content` in padding first, then applies `.glassEffect` so the
/// glass shape grows to match the padded content rather than clipping it
/// (modifier order matters for `.glassEffect` — see the `apple-liquid-glass`
/// skill).
@available(macOS 26.0, *)
public struct GlassCard<Content: View>: View {
    private let cornerRadius: CGFloat
    private let padding: CGFloat
    private let tint: Color?
    private let content: Content

    public init(
        cornerRadius: CGFloat = DSCornerRadius.large,
        padding: CGFloat = DSSpacing.medium,
        tint: Color? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.tint = tint
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .glassEffect(glass, in: .rect(cornerRadius: cornerRadius))
    }

    private var glass: Glass {
        if let tint {
            .regular.tint(tint)
        } else {
            .regular
        }
    }
}

/// Convenience modifier form of `GlassCard`, for applying the same treatment
/// to an existing view hierarchy without an extra wrapper type.
@available(macOS 26.0, *)
public extension View {
    func dsGlassCard(
        cornerRadius: CGFloat = DSCornerRadius.large,
        padding: CGFloat = DSSpacing.medium,
        tint: Color? = nil
    ) -> some View {
        self
            .padding(padding)
            .glassEffect(tint.map { Glass.regular.tint($0) } ?? .regular, in: .rect(cornerRadius: cornerRadius))
    }
}

@available(macOS 26.0, *)
#Preview("Glass Card") {
    ZStack {
        LinearGradient(colors: [.blue, .purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea()

        VStack(spacing: DSSpacing.large) {
            GlassCard {
                VStack(alignment: .leading, spacing: DSSpacing.xSmall) {
                    Text("Last scan").font(DSTypography.heading)
                    Text("3.2 GB reclaimable across 214 items").font(DSTypography.subheading)
                        .foregroundStyle(DSColor.textSecondary)
                }
                .frame(width: 260, alignment: .leading)
            }

            GlassCard(tint: DSColor.destructive.opacity(0.5)) {
                Text("Danger zone").font(DSTypography.heading)
                    .frame(width: 260, alignment: .leading)
            }
        }
        .padding(DSSpacing.xLarge)
    }
    .frame(width: 420, height: 420)
}
