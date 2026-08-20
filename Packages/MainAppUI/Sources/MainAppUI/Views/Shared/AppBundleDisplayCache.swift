import AppKit
import Foundation

/// Caches the human-readable display name and Finder icon for `.app` bundle
/// paths, keyed by path.
///
/// Without this, resolving either value means disk I/O on every call:
/// `NSWorkspace.icon(forFile:)` loads/renders an `NSImage` from the bundle's
/// `.icns` resource, and reading `Info.plist` is a filesystem read plus a
/// plist parse. SwiftUI can re-evaluate a row view's `body` far more often
/// than the underlying `ScanItem` actually changes — e.g. while scrolling a
/// long list, cells are recreated as they enter the visible range — so doing
/// either lookup fresh inside a row's `body` would redo the same disk I/O
/// over and over for the same path. Callers (`FindingsListView`,
/// `UninstallerView`) look up name/icon once per path via this cache instead
/// of on every render.
///
/// `@MainActor`-scoped rather than made `Sendable`: nothing here needs to be
/// called off the main actor — `View.body` already runs on it — so a plain
/// actor-isolated cache is simpler and avoids any lock/queue machinery.
@MainActor
enum AppBundleDisplayCache {
    private static var names: [String: String] = [:]
    private static var icons: [String: NSImage] = [:]

    /// True if `path` looks like an application bundle. Cheap string check —
    /// callers use this to decide whether it's worth consulting the cache at
    /// all, so plain files/directories never pay for a cache lookup.
    static func isAppBundle(_ path: String) -> Bool {
        path.hasSuffix(".app")
    }

    /// Human-readable name for the `.app` bundle at `path`:
    /// `CFBundleDisplayName`, falling back to `CFBundleName`, falling back to
    /// the filename without its `.app` extension. Resolved once per path and
    /// cached thereafter.
    static func displayName(forBundlePath path: String) -> String {
        if let cached = names[path] { return cached }

        let fallback = (path as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
        let resolved: String
        if let info = readInfoPlist(at: path + "/Contents/Info.plist") {
            resolved = (info["CFBundleDisplayName"] as? String)
                ?? (info["CFBundleName"] as? String)
                ?? fallback
        } else {
            resolved = fallback
        }
        names[path] = resolved
        return resolved
    }

    /// The icon `NSWorkspace`/Finder would show for `path`. Resolved once per
    /// path and cached thereafter. Safe to call even if `path` no longer
    /// exists on disk (e.g. a quarantined item's original path) — falls back
    /// to macOS's generic-document icon rather than throwing.
    static func icon(forPath path: String) -> NSImage {
        if let cached = icons[path] { return cached }
        let icon = NSWorkspace.shared.icon(forFile: path)
        icons[path] = icon
        return icon
    }

    private static func readInfoPlist(at path: String) -> [String: Any]? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
    }
}
