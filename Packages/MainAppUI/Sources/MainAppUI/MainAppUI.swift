/// The Phase 2 "Agent:MainAppUI" module: `Capabilities`/`BuildFlavor`
/// (centralized App Store vs. Developer ID feature gating), `AppEnvironment`
/// (the composition root both Xcode app targets share), and the SwiftUI
/// views that assemble `UIDesignSystem` + every feature package into the
/// actual app. See `App/project.yml` for how the two Xcode targets consume
/// this package, and `ARCHITECTURE.md` for the module graph.
public enum MainAppUIModule {
    public static let apiVersion = "1.0.0"
}
