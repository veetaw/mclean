import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// The **only** supported way this package changes a TCC grant: opening the
/// exact System Settings > Privacy & Security pane so the user flips it
/// themselves. macOS does not allow a third-party app to revoke another
/// app's TCC grant programmatically ("macOS non permette revoca
/// programmatica diretta" — product spec), and there is deliberately no
/// `revoke(...)`/`setGrant(...)` method anywhere in this package — this
/// type only ever *opens a Settings pane*, never mutates a grant. See
/// `TCCPermissionReading` for the read half of this split.
public struct TCCSettingsPaneOpener: Sendable {
    public init() {}

    /// Builds the `x-apple.systempreferences:` URL for the pane governing
    /// `service`, or `nil` for a service this type has no mapping for
    /// (callers should fall back to `generalPrivacySettingsURL`).
    ///
    /// These pane anchors are undocumented and have shifted before across
    /// macOS releases (most recently: System Preferences -> System
    /// Settings). Treat this mapping as best-effort, the same way the TCC
    /// database schema is — it may need updating for a future macOS
    /// release.
    public func settingsURL(for service: TCCServiceIdentifier) -> URL? {
        guard let anchor = Self.privacyAnchors[service] else { return nil }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")
    }

    /// The top-level Privacy & Security pane, used as a fallback when
    /// `settingsURL(for:)` has no specific mapping for a service.
    public var generalPrivacySettingsURL: URL {
        // Safe to force-unwrap: a fixed, well-formed literal, never derived
        // from external input.
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")!
    }

    #if canImport(AppKit)
    /// Opens the pane for `service` (or the general Privacy & Security pane
    /// if unmapped) via `NSWorkspace.shared.open(_:)`. Returns `false`
    /// (never throws/crashes) if the URL can't be constructed or opening it
    /// fails — callers should surface that as "please open System Settings
    /// manually."
    @MainActor
    @discardableResult
    public func openSettingsPane(for service: TCCServiceIdentifier) -> Bool {
        let url = settingsURL(for: service) ?? generalPrivacySettingsURL
        return NSWorkspace.shared.open(url)
    }
    #endif

    private static let privacyAnchors: [TCCServiceIdentifier: String] = [
        .camera: "Privacy_Camera",
        .microphone: "Privacy_Microphone",
        .accessibility: "Privacy_Accessibility",
        .fullDiskAccess: "Privacy_AllFiles",
        .screenCapture: "Privacy_ScreenCapture",
        .calendars: "Privacy_Calendars",
        .contacts: "Privacy_Contacts",
        .photos: "Privacy_Photos",
        .reminders: "Privacy_Reminders",
        .automation: "Privacy_Automation",
        .inputMonitoring: "Privacy_ListenEvent",
        .locationServices: "Privacy_LocationServices",
        .bluetooth: "Privacy_Bluetooth",
        .developerTools: "Privacy_DeveloperTool"
    ]
}
