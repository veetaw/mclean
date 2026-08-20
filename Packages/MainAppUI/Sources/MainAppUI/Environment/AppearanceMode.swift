import SwiftUI

/// The user-selectable appearance for the whole app, persisted via
/// `@AppStorage` (see `SettingsView.appearanceMode`) and applied at the
/// `@main App` root as `.preferredColorScheme(_:)`. `RawRepresentable` as
/// `String` so it can be stored directly by `@AppStorage` without a manual
/// int/string mapping layer.
public enum AppearanceMode: String, CaseIterable, Sendable {
    case light
    case dark
    case system

    /// Label shown in the Settings picker.
    public var displayName: String {
        switch self {
        case .light: "Light"
        case .dark: "Dark"
        case .system: "System"
        }
    }

    /// The value to hand to `.preferredColorScheme(_:)`. `nil` for
    /// `.system` tells SwiftUI to defer to the OS appearance setting.
    public var colorScheme: ColorScheme? {
        switch self {
        case .light: .light
        case .dark: .dark
        case .system: nil
        }
    }
}
