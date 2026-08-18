import CoreGraphics

/// Spacing scale used across every MClean Pro surface. Keep call sites on
/// these tokens rather than hardcoded numbers so the whole app's density can
/// be tuned in one place.
public enum DSSpacing {
    /// 4pt — tight gaps within a compound control (e.g. icon-to-badge).
    public static let xxSmall: CGFloat = 4
    /// 8pt — gap between a label and its caption, icon-to-text gaps.
    public static let xSmall: CGFloat = 8
    /// 12pt — default gap between sibling controls in an `HStack`/`VStack`.
    public static let small: CGFloat = 12
    /// 16pt — default padding inside a card/panel.
    public static let medium: CGFloat = 16
    /// 24pt — spacing between distinct sections.
    public static let large: CGFloat = 24
    /// 32pt — spacing between major page regions.
    public static let xLarge: CGFloat = 32
    /// 48pt — outermost page/window margins.
    public static let xxLarge: CGFloat = 48
}
