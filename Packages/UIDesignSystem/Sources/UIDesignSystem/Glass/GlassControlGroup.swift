import SwiftUI

/// A row of related glass controls — a toolbar cluster, a settings-section
/// action row — grouped inside a single `GlassEffectContainer` so they
/// share sampling/blending as Apple's Liquid Glass guidance requires for
/// glass that sits close together.
///
/// This does **not** apply `.glassEffect` itself: each child is expected to
/// supply its own glass (typically via `.buttonStyle(.glass)` or
/// `.dsButtonStyle(_:)`). Placing a raw `.glassEffect` behind an already
/// glass-styled button is the most common Liquid Glass mistake — see the
/// `apple-liquid-glass` skill.
@available(macOS 26.0, *)
public struct GlassControlGroup<Content: View>: View {
    private let spacing: CGFloat
    private let content: Content

    public init(
        spacing: CGFloat = DSSpacing.small,
        @ViewBuilder content: () -> Content
    ) {
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        GlassEffectContainer(spacing: spacing) {
            HStack(spacing: spacing) {
                content
            }
        }
    }
}

@available(macOS 26.0, *)
#Preview("Glass Control Group") {
    ZStack {
        LinearGradient(colors: [.indigo, .teal], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()

        VStack(spacing: DSSpacing.large) {
            GlassControlGroup {
                Button("Rescan", systemImage: "arrow.clockwise") {}
                    .dsButtonStyle(.secondary)
                Button("Clean Now", systemImage: "trash") {}
                    .dsButtonStyle(.primary)
            }

            GlassControlGroup {
                Button("Empty Quarantine", systemImage: "xmark.bin") {}
                    .dsButtonStyle(.destructive)
            }
        }
        .padding(DSSpacing.xLarge)
    }
    .frame(width: 480, height: 260)
}
