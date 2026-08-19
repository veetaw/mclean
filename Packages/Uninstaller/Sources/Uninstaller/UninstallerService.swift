import Foundation
import CoreScanEngine
import PowerUserInspectors

/// Finds every filesystem artifact plausibly left behind by one installed
/// app — the `.app` bundle itself plus its `Application Support`,
/// `Preferences`, `Caches`, `Saved Application State`, `LaunchAgents`, and a
/// handful of other well-known `~/Library` locations — for preview ahead of
/// removal. See PROMPT MASTER §5.1: "Uninstaller completo: rimuove l'app +
/// tutti i file correlati ..., con anteprima di ogni file trovato."
///
/// **This type is strictly read-only.** It never deletes, moves, renames, or
/// modifies anything — `relatedFiles(for:)` only walks the filesystem and
/// returns `ScanItem`s describing what it found. Actual removal is entirely
/// out of scope for this package: the caller (`MainAppUI`) feeds the
/// returned items through the exact same `SafetyClassifier` →
/// `QuarantineConfirmationSheet` → `FileSystemQuarantineManager` flow used
/// for every other kind of scan result, so denylist checks, confirmation,
/// and quarantine-based (reversible) deletion all happen downstream, outside
/// this package.
///
/// Unlike `DevToolsDetectors`/`CacheCleaner`/etc., this is deliberately
/// **not** a `CoreScanEngine.Detector` registered with `ScanEngine` for
/// every full scan — uninstalling is an explicit, per-app, user-initiated
/// action ("remove THIS app"), not something to enumerate for every app on
/// every routine scan. It follows the same "plain callable service" shape
/// already established by `PowerUserInspectors.ConfigFileExplorer` and
/// `PowerUserInspectors.PackageExplorer`.
///
/// ## Matching strategy (bundle ID first, name only as a conservative fallback)
///
/// Every location below is matched primarily by `bundleIdentifier`, using a
/// dot-boundary prefix rule: a directory/file entry named exactly the bundle
/// identifier, or beginning with `"<bundleIdentifier>."`, is considered
/// related. That boundary is deliberate — it catches legitimate variants
/// like a helper process's `com.example.myapp.helper.plist` or a saved-state
/// bundle's `com.example.myapp.savedState`, while `com.example.myapp2...`
/// (a different app that merely shares a prefix) is correctly rejected
/// because there's no `.` right after `myapp`.
///
/// When `bundleIdentifier` is `nil` (or empty), matching falls back to the
/// app's display `name` — but only for the two `~/Library` locations where
/// apps are commonly keyed by display name instead of a reverse-DNS
/// identifier (`Application Support`, `Caches`), and only as an **exact**
/// directory-name match, never a prefix scan. Every other, reverse-DNS-keyed
/// location (`Preferences`, `Saved Application State`, `LaunchAgents`,
/// `Containers`, ...) is skipped entirely when there's no bundle ID, because
/// guessing a reverse-DNS-style identifier from a display name is far more
/// likely to either miss the real files or, worse, collide with an unrelated
/// file that happens to share the same name. This is a conservative,
/// documented trade-off: **false negatives (missing some of a
/// no-bundle-ID app's leftovers) are preferred over false positives
/// (flagging an unrelated app's files)** — the preview is only useful if the
/// user can trust it.
public struct UninstallerService: Sendable {
    /// Stable identifier recorded on every `ScanItem.sourceDetectorID` this
    /// service produces, even though it isn't a `Detector`.
    public static let sourceID = "uninstaller.related-files"

    private let homeDirectory: URL
    private let userLibraryDirectory: URL
    private let systemLibraryDirectory: URL

    /// - Parameters:
    ///   - homeDirectory: Defaults to the real user's home directory.
    ///     Tests pass a temp directory so nothing here ever touches the
    ///     real `~/Library`.
    ///   - systemLibraryDirectory: Defaults to `/Library`. Tests pass a temp
    ///     directory for the same reason.
    public init(
        homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory()),
        systemLibraryDirectory: URL = URL(fileURLWithPath: "/Library")
    ) {
        self.homeDirectory = homeDirectory
        self.userLibraryDirectory = homeDirectory.appendingPathComponent("Library", isDirectory: true)
        self.systemLibraryDirectory = systemLibraryDirectory
    }

    /// Finds every candidate file/directory related to `app`, for preview.
    /// Purely synchronous filesystem enumeration — no network, no
    /// subprocesses, and (per the type's own contract) no writes.
    ///
    /// Every returned `ScanItem` is a *candidate*: nothing has been deleted,
    /// moved, or otherwise touched. Items under paths this process can't
    /// actually remove without elevated privileges (see the `/Library`
    /// LaunchAgents/LaunchDaemons handling below) are still included, with
    /// an honest `reason` saying so, so the preview stays complete even
    /// though acting on those specific items may fail later without an
    /// admin prompt this build doesn't yet request.
    public func relatedFiles(for app: PowerUserInspectors.InstalledApp) -> [ScanItem] {
        var items: [ScanItem] = []
        var seenPaths = Set<String>()

        func addIfExists(path: String, category: String, reason: String) {
            guard UninstallerFS.exists(path) else { return }
            let normalized = (path as NSString).standardizingPath
            guard seenPaths.insert(normalized).inserted else { return }
            items.append(ScanItem(
                path: path,
                sizeBytes: UninstallerFS.recursiveSize(of: path),
                sourceDetectorID: Self.sourceID,
                category: category,
                lastUsed: nil,
                reason: reason
            ))
        }

        func addMatches(inDirectory directory: URL, identifier: String, category: String, reason: (String) -> String) {
            let directoryPath = directory.path
            for entry in UninstallerFS.directoryEntries(directoryPath) where Self.isDotBoundaryMatch(entry, identifier: identifier) {
                addIfExists(path: directoryPath + "/" + entry, category: category, reason: reason(entry))
            }
        }

        // 1. The app bundle itself — always included, one item.
        addIfExists(
            path: app.path,
            category: "Application bundle",
            reason: "The \(app.name) application bundle itself."
        )

        let trimmedBundleIdentifier = app.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        let bundleIdentifier = (trimmedBundleIdentifier?.isEmpty == false) ? trimmedBundleIdentifier! : nil

        // 2. Application Support — apps inconsistently key this by bundle
        // identifier or by display name, so both are tried regardless of
        // which is available.
        let applicationSupport = userLibraryDirectory.appendingPathComponent("Application Support", isDirectory: true)
        if let bundleIdentifier {
            addIfExists(
                path: applicationSupport.appendingPathComponent(bundleIdentifier, isDirectory: true).path,
                category: "Application Support",
                reason: "Application Support data keyed by bundle identifier \(bundleIdentifier)."
            )
        }
        addIfExists(
            path: applicationSupport.appendingPathComponent(app.name, isDirectory: true).path,
            category: "Application Support",
            reason: "Application Support data keyed by application name \(app.name)."
        )

        // 3. Preferences — reverse-DNS-keyed by convention; only matched
        // when a bundle identifier is available (see matching-strategy doc
        // comment above).
        if let bundleIdentifier {
            addMatches(
                inDirectory: userLibraryDirectory.appendingPathComponent("Preferences", isDirectory: true),
                identifier: bundleIdentifier,
                category: "Preferences"
            ) { entry in "Preferences file \(entry) matching bundle identifier \(bundleIdentifier)." }
        }

        // 4. Caches — bundle-identifier match plus, since some apps use
        // their display name here too, an exact name-keyed fallback.
        let caches = userLibraryDirectory.appendingPathComponent("Caches", isDirectory: true)
        if let bundleIdentifier {
            addMatches(inDirectory: caches, identifier: bundleIdentifier, category: "Caches") { entry in
                "Cache directory \(entry) matching bundle identifier \(bundleIdentifier)."
            }
        }
        addIfExists(
            path: caches.appendingPathComponent(app.name, isDirectory: true).path,
            category: "Caches",
            reason: "Cache directory keyed by application name \(app.name)."
        )

        // 5. Saved Application State — reverse-DNS-keyed; bundle ID only.
        if let bundleIdentifier {
            addMatches(
                inDirectory: userLibraryDirectory.appendingPathComponent("Saved Application State", isDirectory: true),
                identifier: bundleIdentifier,
                category: "Saved Application State"
            ) { entry in "Saved window/UI state \(entry) matching bundle identifier \(bundleIdentifier)." }
        }

        // 6. LaunchAgents — user-level agents are removable by this
        // process; the per-user directory is fully user-writable.
        if let bundleIdentifier {
            addMatches(
                inDirectory: userLibraryDirectory.appendingPathComponent("LaunchAgents", isDirectory: true),
                identifier: bundleIdentifier,
                category: "LaunchAgents (user)"
            ) { entry in "User LaunchAgent \(entry) matching bundle identifier \(bundleIdentifier)." }

            // 7. /Library/LaunchAgents — installed system-wide by an
            // installer running as admin; listed for a complete preview,
            // but honestly flagged: actually removing a file here typically
            // needs root, which this app does not currently request for
            // uninstaller actions.
            addMatches(
                inDirectory: systemLibraryDirectory.appendingPathComponent("LaunchAgents", isDirectory: true),
                identifier: bundleIdentifier,
                category: "LaunchAgents (system)"
            ) { entry in
                "System-wide LaunchAgent \(entry) matching bundle identifier \(bundleIdentifier). " +
                "Listed for a complete preview; actually removing this file may require administrator " +
                "privileges this app does not currently request."
            }

            // 8. /Library/LaunchDaemons — root-owned; listed for
            // completeness only. Removal here needs an elevated helper this
            // build doesn't have, so the reason says so explicitly rather
            // than implying a plain user-space delete will succeed.
            addMatches(
                inDirectory: systemLibraryDirectory.appendingPathComponent("LaunchDaemons", isDirectory: true),
                identifier: bundleIdentifier,
                category: "LaunchDaemons (system)"
            ) { entry in
                "System LaunchDaemon \(entry) matching bundle identifier \(bundleIdentifier). " +
                "Listed for a complete preview only — LaunchDaemons are root-owned, and this app has no " +
                "privileged-removal path for them yet, so this item likely cannot actually be removed " +
                "without administrator privileges this build doesn't request."
            }

            // 9. Best-effort catch-all across a few other well-known
            // ~/Library locations that are commonly bundle-ID-keyed:
            //   - HTTPStorages: per-app HTTP cookie/cache storage.
            //   - WebKit: per-app WebKit website data (WKWebView apps).
            //   - Containers: App Sandbox container directories, named
            //     exactly the bundle ID (plus dot-suffixed variants for
            //     app extensions, e.g. a Share Extension's own container).
            //   - Application Scripts: sandboxed apps' AppleScript
            //     dictionaries, also keyed by bundle ID.
            // Deliberately NOT included: `~/Library/Group Containers`
            // (keyed by App Group identifier, which has no reliable
            // relationship to the bundle identifier — guessing here risks
            // matching an unrelated app that happens to share the group),
            // and `~/Library/Logs` (log file/directory names are often
            // generic or product-name-based rather than bundle-ID-based,
            // and log directories are frequently shared across unrelated
            // tools from the same vendor — too high a false-positive risk
            // for an automatic match).
            let catchAllLocations: [(directoryName: String, category: String)] = [
                ("HTTPStorages", "HTTPStorages"),
                ("WebKit", "WebKit website data"),
                ("Containers", "App Sandbox container"),
                ("Application Scripts", "Sandboxed Application Scripts")
            ]
            for location in catchAllLocations {
                addMatches(
                    inDirectory: userLibraryDirectory.appendingPathComponent(location.directoryName, isDirectory: true),
                    identifier: bundleIdentifier,
                    category: location.category
                ) { entry in "\(location.category) entry \(entry) matching bundle identifier \(bundleIdentifier)." }
            }
        }

        return items
    }

    /// `true` if `entryName` is exactly `identifier`, or begins with
    /// `"<identifier>."` — the dot-boundary prefix rule documented on this
    /// type. This deliberately rejects a merely-shared string prefix like
    /// `identifier = "com.example.myapp"` matching an entry named
    /// `"com.example.myapp2.plist"` (no `.` immediately after `myapp`),
    /// while still matching `"com.example.myapp.helper.plist"` and
    /// `"com.example.myapp.savedState"`.
    static func isDotBoundaryMatch(_ entryName: String, identifier: String) -> Bool {
        entryName == identifier || entryName.hasPrefix(identifier + ".")
    }
}
