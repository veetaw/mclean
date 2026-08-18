import Foundation

/// Hardcoded, compiled-in denylist. This is intentionally **not** loaded from
/// any configuration file and has no UI path to disable or edit it — see
/// PROMPT MASTER §2: "Denylist hardcoded, non bypassabile da UI".
///
/// This type only answers "is this path forbidden", it does not delete or
/// move anything. It is meant to be consulted first, unconditionally, by
/// whatever implements `SafetyClassifying`, before any user-editable rule
/// (including `safe-auto` rules) gets a say.
public enum Denylist {
    /// Absolute path prefixes that are never eligible for any destructive
    /// action, regardless of user settings.
    public static let forbiddenPathPrefixes: [String] = [
        "/System",
        "/private/var/db",
        "/Library/Keychains",
        "/dev",
        "/Volumes", // boot/external volume roots themselves, not arbitrary
                    // user files *within* a mounted volume — see `isForbidden`.
    ]

    /// `/usr` is forbidden except the subtree Homebrew actually manages
    /// (`/usr/local`), which the user relies on this app to help clean.
    public static let usrAllowedSubprefix = "/usr/local"

    /// Filename patterns that are forbidden anywhere on disk, not just under
    /// the path prefixes above (e.g. an active kernel extension found inside
    /// a user's project checkout should still never be auto-suggested).
    public static let forbiddenFilenamePatterns: [String] = [
        ".kext",            // kernel extensions
        ".license",         // license files — never guess these are junk
    ]

    /// Returns non-nil with a human-readable reason if `path` is forbidden.
    /// Callers must treat a non-nil result as absolute: never surface this
    /// item as deletable in any UI, even in an "advanced"/"override" mode.
    public static func forbiddenReason(forPath path: String) -> String? {
        let normalized = (path as NSString).standardizingPath

        if normalized.hasPrefix("/usr") && !normalized.hasPrefix(usrAllowedSubprefix) {
            return "Under /usr and outside the Homebrew-managed /usr/local subtree."
        }

        for prefix in forbiddenPathPrefixes where normalized == prefix || normalized.hasPrefix(prefix + "/") {
            return "Under protected system path \(prefix)."
        }

        let filename = (normalized as NSString).lastPathComponent
        for pattern in forbiddenFilenamePatterns where filename.hasSuffix(pattern) {
            return "Matches protected filename pattern \"\(pattern)\"."
        }

        return nil
    }

    /// Volume/boot-disk check is intentionally separate from path-prefix
    /// matching: it needs to ask the OS which volume is the startup disk
    /// rather than pattern-match a string. Implemented where filesystem APIs
    /// are available (not in this pure-logic package) and layered on top of
    /// `forbiddenReason` — see `SafetyClassifying` composition.
    public static func isLikelyBootVolumeRoot(_ path: String) -> Bool {
        let normalized = (path as NSString).standardizingPath
        // A volume root looks like "/" or "/Volumes/<Name>" with nothing after.
        if normalized == "/" { return true }
        if normalized.hasPrefix("/Volumes/") {
            let remainder = normalized.dropFirst("/Volumes/".count)
            return !remainder.contains("/")
        }
        return false
    }
}
