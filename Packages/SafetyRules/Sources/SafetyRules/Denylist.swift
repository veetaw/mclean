import Foundation

/// Hardcoded, compiled-in denylist. This is intentionally **not** loaded from
/// any configuration file and has no UI path to disable or edit it — see
/// PROMPT MASTER §2: "Denylist hardcoded, non bypassabile da UI".
///
/// This type only answers "is this path forbidden", it does not delete or
/// move anything. It is meant to be consulted first, unconditionally, by
/// whatever implements `SafetyClassifying`, before any user-editable rule
/// (including `safe-auto` rules) gets a say.
///
/// As of checkpoint 4's closure, this type is no longer pure string
/// matching: `forbiddenReason(forPath:)` also walks the filesystem (to find
/// an enclosing `.git` directory) and may shell out to `git status`. Both
/// are synchronous, bounded, fail-safe operations — see
/// `isInsideDirtyGitRepository` — so `forbiddenReason` stays a plain
/// synchronous function rather than forcing every caller (including
/// `SafetyClassifier.classify`) to become `async`.
public enum Denylist {
    /// Absolute path prefixes that are never eligible for any destructive
    /// action, regardless of user settings.
    public static let forbiddenPathPrefixes: [String] = [
        "/System",
        "/private/var/db",
        "/Library/Keychains",
        "/dev",
        // NOTE: `/Volumes` itself is deliberately NOT in this list. Volume
        // *roots* (the mount point itself, e.g. "/Volumes/Macintosh HD")
        // are forbidden separately, exactly, via `isLikelyBootVolumeRoot`
        // (checked by `SafetyClassifier` right after `forbiddenReason`).
        // Ordinary files *within* an external/network volume are legitimate
        // to propose for confirmed (not automatic) cleanup — see
        // `isOnNonBootVolume`, which downgrades a would-be `safeAuto`
        // verdict to `needsConfirmation` for anything outside the boot
        // volume rather than forbidding it outright (checkpoint 4). An
        // earlier version of this list included a bare "/Volumes" prefix,
        // which — despite this same comment's original intent — actually
        // forbade every file on every external volume outright; fixed as
        // part of closing checkpoint 4, caught by
        // `DenylistCheckpoint4Tests.testExternalVolumeIsNotForbiddenButIsFlaggedNonBoot`.
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
        ".env",             // environment files — routinely hold live secrets,
                             // even when found inside an otherwise-safe cache
                             // or build directory (checkpoint 4).
        ".pem",             // certificates/private keys (checkpoint 4).
        ".key",             // private keys (checkpoint 4).
    ]

    /// Home-relative directories that hold credentials for cloud/CLI
    /// tooling — added per checkpoint 4 ("directory equivalenti di
    /// credenziali cloud/CLI"). Explicitly requested: `.ssh`, `.gnupg`,
    /// `.aws`, `.config/gcloud`. Added by direct extension of that same
    /// category (flagged here for review, not silently assumed): `.kube`
    /// (Kubernetes config/credentials) and `.azure` (Azure CLI).
    public static let forbiddenHomeRelativeCredentialDirectories: [String] = [
        ".ssh",
        ".gnupg",
        ".aws",
        ".config/gcloud",
        ".kube",
        ".azure",
    ]

    /// Returns non-nil with a human-readable reason if `path` is forbidden.
    /// Callers must treat a non-nil result as absolute: never surface this
    /// item as deletable in any UI, even in an "advanced"/"override" mode.
    ///
    /// Checks, in order (cheapest first): path prefixes, credential
    /// directories, filename patterns, then — only if nothing above already
    /// matched — whether the path sits inside a git repository with
    /// uncommitted changes.
    public static func forbiddenReason(forPath path: String, homeDirectory: String = NSHomeDirectory()) -> String? {
        let normalized = (path as NSString).standardizingPath

        if normalized.hasPrefix("/usr") && !normalized.hasPrefix(usrAllowedSubprefix) {
            return "Under /usr and outside the Homebrew-managed /usr/local subtree."
        }

        for prefix in forbiddenPathPrefixes where normalized == prefix || normalized.hasPrefix(prefix + "/") {
            return "Under protected system path \(prefix)."
        }

        let normalizedHome = (homeDirectory as NSString).standardizingPath
        for relative in forbiddenHomeRelativeCredentialDirectories {
            let credentialPath = normalizedHome + "/" + relative
            if normalized == credentialPath || normalized.hasPrefix(credentialPath + "/") {
                return "Under a credential directory (~/\(relative)) — never eligible for cleanup."
            }
        }

        let filename = (normalized as NSString).lastPathComponent
        for pattern in forbiddenFilenamePatterns where filename.hasSuffix(pattern) {
            return "Matches protected filename pattern \"\(pattern)\"."
        }

        if let gitReason = dirtyGitRepositoryReason(forPath: normalized) {
            return gitReason
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

    /// Checkpoint 4: "Volumi esterni/di rete montati (mai proporre pulizia
    /// automatica fuori dal disco di boot)". This is intentionally *not*
    /// folded into `forbiddenReason` — an external/network volume isn't
    /// forbidden to clean with the user's explicit per-item confirmation,
    /// only ineligible for the unattended `safe-auto` tier. See
    /// `SafetyClassifier`, which downgrades a would-be `safeAuto` verdict
    /// to `needsConfirmation` whenever this returns `true`.
    ///
    /// Simplification: anything under `/Volumes/` is treated as a non-boot
    /// volume, and everything else as the boot volume. This doesn't account
    /// for exotic mount setups, but matches how external/network drives
    /// actually appear on a default macOS install.
    public static func isOnNonBootVolume(_ path: String) -> Bool {
        let normalized = (path as NSString).standardizingPath
        return normalized.hasPrefix("/Volumes/")
    }

    // MARK: - Dirty git repository check (checkpoint 4)

    /// Walks upward from `path` looking for the nearest enclosing `.git`
    /// directory (bounded — see `maxAncestorWalk`), and if found, checks
    /// whether that repository has uncommitted changes via
    /// `git status --porcelain`. A path inside such a repository is
    /// forbidden, universally, for every detector — this is enforced once,
    /// here, at the shared classification chokepoint, rather than
    /// duplicated per detector (PROMPT MASTER's own SAFETY_RULES.md note:
    /// "check git status before proposing cleanup of a repo").
    ///
    /// Fails safe-but-not-blocking: if `git` isn't installed, the walk
    /// doesn't find a `.git` directory, or the subprocess fails for any
    /// reason, this returns `nil` (not forbidden via *this* rule) rather
    /// than throwing or hanging — the item still defaults to
    /// `needsConfirmation` via `SafetyClassifier`'s normal fallback, so
    /// nothing becomes silently auto-cleanable just because this check
    /// couldn't run.
    static func dirtyGitRepositoryReason(forPath path: String) -> String? {
        guard let repoRoot = findEnclosingGitRepository(startingAt: path) else { return nil }
        guard isGitRepositoryDirty(atRoot: repoRoot) else { return nil }
        return "Inside a git repository (\(repoRoot)) with uncommitted changes."
    }

    /// How many parent directories to check before giving up — avoids an
    /// unbounded walk for a path with an unusually deep hierarchy.
    private static let maxAncestorWalk = 32

    private static func findEnclosingGitRepository(startingAt path: String, fileManager: FileManager = .default) -> String? {
        var current = URL(fileURLWithPath: path).standardizedFileURL
        // The candidate path might itself be a file (e.g. a stray `.pem`);
        // start the walk from its containing directory when it isn't
        // itself a directory that could contain `.git`.
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: current.path, isDirectory: &isDirectory), !isDirectory.boolValue {
            current = current.deletingLastPathComponent()
        }

        for _ in 0..<maxAncestorWalk {
            let gitDir = current.appendingPathComponent(".git")
            if fileManager.fileExists(atPath: gitDir.path) {
                return current.path
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break } // reached "/"
            current = parent
        }
        return nil
    }

    private static func isGitRepositoryDirty(atRoot repoRoot: String, timeout: TimeInterval = 3) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", repoRoot, "status", "--porcelain"]

        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe() // discarded; a git error just means "can't tell"

        do {
            try process.run()
        } catch {
            return false // git not installed / not launchable — fail open (see doc above)
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            usleep(10_000) // 10ms poll — bounded by `timeout`
        }
        if process.isRunning {
            process.terminate()
            return false // didn't finish in time — fail open rather than hang the caller
        }

        guard process.terminationStatus == 0 else { return false }
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        return !data.isEmpty
    }
}
