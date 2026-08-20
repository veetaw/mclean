import AppKit
import CoreScanEngine

/// Resolves the title and icon `ScanResultRow` should show for a
/// `CoreScanEngine.ScanItem`.
///
/// Lives here (not in `ScanResultRow` itself) deliberately —
/// `UIDesignSystem` has no dependency on feature packages and `ScanResultRow`
/// takes plain values, not a `ScanItem`; `.app`-bundle detection belongs at
/// the call site, which is what this type centralizes so `FindingsListView`
/// and `UninstallerView` don't duplicate the same `.hasSuffix(".app")` check
/// and cache plumbing.
@MainActor
enum ScanItemRowDisplay {
    /// For `.app` bundles: the resolved display name (e.g. "Google Chrome")
    /// instead of the detector's generic `category` (e.g. "Installed
    /// application", which is identical across every row and tells the user
    /// nothing). For everything else: `item.category`, unchanged. The full
    /// path is always the subtitle at the call site — this only affects the
    /// title.
    static func title(for item: ScanItem) -> String {
        guard AppBundleDisplayCache.isAppBundle(item.path) else { return item.category }
        return AppBundleDisplayCache.displayName(forBundlePath: item.path)
    }

    /// Real bundle icon for `.app` items; `nil` for everything else so
    /// callers fall back to their existing SF Symbol glyph.
    static func icon(for item: ScanItem) -> NSImage? {
        guard AppBundleDisplayCache.isAppBundle(item.path) else { return nil }
        return AppBundleDisplayCache.icon(forPath: item.path)
    }
}
