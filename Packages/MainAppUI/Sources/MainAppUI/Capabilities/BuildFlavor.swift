import Foundation

/// Which of the two shipping build flavors this binary was compiled as.
///
/// This is the **single** call site in the whole app that reads the
/// `APPSTORE` compilation condition (`#if APPSTORE`, set by
/// `App/project.yml` via `SWIFT_ACTIVE_COMPILATION_CONDITIONS` on the
/// `MCleanPro-AppStore` target only). Every other file — views, view
/// models, `AppEnvironment` — must ask `Capabilities`, never sprinkle its
/// own `#if APPSTORE`. See PROMPT MASTER §3: "registry runtime Capabilities
/// + flag di compilazione `#if APPSTORE` per gating centralizzato delle
/// feature, non `#if` sparsi ovunque."
public enum BuildFlavor: String, Sendable, Hashable, CaseIterable {
    /// Sandboxed, distributed through the Mac App Store. No privileged
    /// helper, no LAN server, restricted filesystem access (user-selected
    /// files only, via the sandbox's security-scoped bookmarks).
    case appStore
    /// Not sandboxed, distributed outside the App Store (notarized
    /// Developer ID build). Full filesystem access (subject to the same
    /// `SafetyRules` denylist/classification as everywhere else), the
    /// `RemoteControlServer` LAN listener, and the `PrivilegedHelper` XPC
    /// service are all available.
    case developerID

    /// Resolved once, here, from the compiler flag. Nothing downstream of
    /// this property should ever need to know `#if APPSTORE` exists.
    public static var current: BuildFlavor {
        #if APPSTORE
        .appStore
        #else
        .developerID
        #endif
    }
}
