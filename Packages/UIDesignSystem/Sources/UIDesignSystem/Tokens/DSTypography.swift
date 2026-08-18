import SwiftUI

/// Typography scale built on the system font and SwiftUI's built-in text
/// styles, so every size participates in macOS's "larger text"
/// accessibility setting the same way system apps do — no fixed point sizes.
public enum DSTypography {
    /// Page/window-level title, e.g. "MClean Pro" in an onboarding screen.
    public static let largeTitle = Font.system(.largeTitle, design: .default, weight: .bold)
    /// Section title, e.g. a settings pane header.
    public static let title = Font.system(.title2, design: .default, weight: .semibold)
    /// Row/card heading, e.g. a `ScanResultRow` title.
    public static let heading = Font.system(.headline, design: .default, weight: .medium)
    /// Default body copy.
    public static let body = Font.system(.body, design: .default, weight: .regular)
    /// Secondary/supporting copy, e.g. a row subtitle or a path.
    public static let subheading = Font.system(.subheadline, design: .default, weight: .regular)
    /// Smallest supporting copy, e.g. a size label or a badge.
    public static let caption = Font.system(.caption, design: .default, weight: .regular)
    /// Emphasized caption, e.g. a badge label that must read as serious.
    public static let captionStrong = Font.system(.caption, design: .default, weight: .semibold)
}
