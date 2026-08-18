import AppKit
import SwiftUI

/// Semantic color palette for MClean Pro. Every token adapts automatically
/// to the system appearance (light/dark) via `NSColor`'s dynamic provider —
/// there is no manual dark-mode branching required at call sites.
///
/// Neutral tokens (background/surface/text/separator) intentionally reuse
/// AppKit's own dynamic system colors rather than reinventing them, so this
/// app matches system chrome exactly. Accent/status tokens are custom, hand
/// tuned for both appearances.
public enum DSColor {
    // MARK: Neutrals (system-backed)

    /// Window-level background.
    public static let background = Color(nsColor: .windowBackgroundColor)
    /// Default surface for a card/panel's content, before glass is applied.
    public static let surface = Color(nsColor: .controlBackgroundColor)
    /// Primary label color.
    public static let textPrimary = Color(nsColor: .labelColor)
    /// Secondary/supporting label color (subtitles, captions, paths).
    public static let textSecondary = Color(nsColor: .secondaryLabelColor)
    /// Tertiary label color (disabled/very low-emphasis text).
    public static let textTertiary = Color(nsColor: .tertiaryLabelColor)
    /// Hairline separators between rows/sections.
    public static let separator = Color(nsColor: .separatorColor)

    // MARK: Brand & status (custom, light/dark tuned)

    /// App accent color, used for the single primary action on a screen.
    public static let accent = dynamic(
        light: NSColor(srgbRed: 0.20, green: 0.47, blue: 0.98, alpha: 1),
        dark: NSColor(srgbRed: 0.35, green: 0.58, blue: 1.0, alpha: 1)
    )

    /// Positive/safe status — used for `safeAuto` verdicts and success states.
    public static let safe = dynamic(
        light: NSColor(srgbRed: 0.16, green: 0.62, blue: 0.36, alpha: 1),
        dark: NSColor(srgbRed: 0.32, green: 0.78, blue: 0.49, alpha: 1)
    )

    /// Caution status — used for `needsConfirmation` verdicts.
    public static let warning = dynamic(
        light: NSColor(srgbRed: 0.80, green: 0.55, blue: 0.02, alpha: 1),
        dark: NSColor(srgbRed: 0.95, green: 0.70, blue: 0.20, alpha: 1)
    )

    /// Destructive/forbidden status. Deliberately more saturated and darker
    /// than a typical system red so it reads as *serious* — this app's
    /// destructive actions matter for user safety.
    public static let destructive = dynamic(
        light: NSColor(srgbRed: 0.75, green: 0.10, blue: 0.13, alpha: 1),
        dark: NSColor(srgbRed: 0.95, green: 0.29, blue: 0.29, alpha: 1)
    )

    // MARK: - Dynamic color construction

    /// Builds a `Color` that resolves to `light` or `dark` based on the
    /// active `NSAppearance`, matching the vanilla appearances an app can
    /// actually be in on macOS.
    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark ? dark : light
        })
    }
}
