import CoreGraphics

/// Corner radius scale used for glass panels, cards, and controls. Prefer
/// `ConcentricRectangle`/`.rect(cornerRadius:)` built from these tokens over
/// ad-hoc radii, so nested shapes stay visually concentric per the Liquid
/// Glass HIG guidance.
public enum DSCornerRadius {
    /// 8pt — small controls, chips, and badges.
    public static let small: CGFloat = 8
    /// 12pt — compact rows and list cells.
    public static let medium: CGFloat = 12
    /// 16pt — standard cards and panels.
    public static let large: CGFloat = 16
    /// 24pt — large surfaces (sheets, settings panes).
    public static let xLarge: CGFloat = 24
    /// A radius large enough to always resolve to a fully rounded (capsule)
    /// edge, regardless of the view's height.
    public static let pill: CGFloat = 999
}
