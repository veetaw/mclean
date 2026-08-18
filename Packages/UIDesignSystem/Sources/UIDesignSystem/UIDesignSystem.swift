/// Shared Liquid Glass component library used by the main app, the menu bar
/// popover, and onboarding flows.
///
/// `UIDesignSystem` has no dependencies of its own (see `Package.swift`) — it
/// only builds on `SwiftUI`/`AppKit`. Everything in this module falls into
/// one of three layers:
///
/// - **Tokens** (`Tokens/`) — spacing, corner radius, semantic color, and
///   typography scales. Every other file in this module is built from these;
///   feature modules should prefer the tokens over hardcoded constants.
/// - **Glass primitives** (`Glass/`) — thin, reusable wrappers around
///   `.glassEffect`, `GlassEffectContainer`, and the `.glass`/`.glassProminent`
///   button styles (see the `apple-liquid-glass` skill for the underlying
///   API surface). These carry no app-specific vocabulary.
/// - **Composed components** (`Components/`) — higher-level views built from
///   the two layers above that speak this app's actual UI vocabulary, e.g.
///   `ScanResultRow` and `SafetyBadge`.
///
/// All Liquid Glass APIs used here require macOS 26. This package's
/// `platforms` floor is intentionally kept at `.v15` (matching every other
/// package in this monorepo) so it still builds in tooling that doesn't yet
/// expose the macOS 26 SDK — every glass-touching declaration below is
/// therefore explicitly marked `@available(macOS 26.0, *)` rather than
/// relying on the package-wide deployment target.
public enum UIDesignSystemModule {
    /// Semantic version of this module's public API surface, bumped whenever
    /// the token or component vocabulary changes in a way other modules
    /// should be aware of.
    public static let apiVersion = "1.0.0"
}
