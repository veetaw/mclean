import Foundation

/// Configuration for `LargeOldFilesFinder`.
///
/// ## Qualification rule
/// A file is reported when:
/// - its size in bytes is `>= minimumSizeBytes`, **and**
/// - `minimumAgeDays` is `nil`, **or** its filesystem modification date is
///   at least that many days in the past, **and**
/// - `fileTypeFilter` is `nil`, **or** its extension belongs to one of the
///   selected categories.
///
/// Size and age are combined with AND by default (100 MB *and* ~6 months
/// old) because the point of a "Large & Old" finder is decluttering big
/// things nobody has touched in a while — a multi-gigabyte video downloaded
/// yesterday probably isn't clutter yet. Either side can be relaxed
/// independently to get a pure single-criterion finder:
/// - **size-only**: set `minimumAgeDays = nil`.
/// - **age-only** (any size, just old): set `minimumSizeBytes = 0`.
public struct LargeOldFilesFinderConfig: Sendable {

    /// 100 MB — large enough to matter for disk space, small enough to
    /// still catch e.g. a single stray video or disk image.
    public static let defaultMinimumSizeBytes: Int64 = 100 * 1024 * 1024

    /// ~6 months. Long enough that actively-used large files (a video
    /// project in progress, this month's downloads) aren't flagged.
    public static let defaultMinimumAgeDays: Int = 180

    /// Common user-facing directories this finder scopes itself to by
    /// default, resolved relative to each root in `ScanContext.roots` (or
    /// the real home directory when that's empty — see
    /// `LargeOldFilesFinder.scan(context:)`).
    ///
    /// Deliberately narrow: this is *not* a blind recursive walk of the
    /// entire home directory. `~/Library/**`, dotfile config directories,
    /// and developer/mobile toolchain trees are all excluded — those are
    /// DevToolsDetectors' / MobileDevDetectors' / PowerUserInspectors'
    /// territory, not this finder's.
    public static let defaultScopedDirectories: [String] = [
        "Downloads", "Desktop", "Documents", "Movies", "Music", "Pictures"
    ]

    /// Directory *names*, wherever encountered during the walk, that this
    /// finder never descends into — either because another detector already
    /// owns that territory (`node_modules`, `.git`, `Library`) or because
    /// it's noise irrelevant to "the user's own large files"
    /// (Spotlight/filesystem-journal metadata directories).
    public static let defaultSkippedDirectoryNames: Set<String> = [
        ".git", ".Trash", "node_modules", "Library", "__pycache__",
        ".build", "DerivedData", ".venv", "venv", "Pods",
        ".Spotlight-V100", ".fseventsd", ".DocumentRevisions-V100"
    ]

    /// Directory *extensions* treated as opaque bundles/packages and never
    /// descended into — apps, frameworks, plugins, and similar are single
    /// logical units (typically the Uninstaller module's territory), not a
    /// tree of individually-reportable "old files".
    public static let defaultSkippedDirectoryExtensions: Set<String> = [
        "app", "framework", "bundle", "plugin", "kext", "prefpane",
        "qlgenerator", "saver", "appex", "xcodeproj", "xcworkspace",
        "photoslibrary"
    ]

    /// `nil` (the default) means: size and/or age thresholds alone decide
    /// whether a file qualifies, regardless of its type.
    public var fileTypeFilter: Set<LargeOldFileTypeCategory>?

    public var minimumSizeBytes: Int64
    public var minimumAgeDays: Int?
    public var scopedDirectories: [String]
    public var skippedDirectoryNames: Set<String>
    public var skippedDirectoryExtensions: Set<String>

    /// Depth limit for the directory walk under each scoped root, so a
    /// pathological deeply-nested tree (or a symlink-free but very deep
    /// project checked out under `~/Downloads`) can't run unbounded. 12
    /// levels comfortably covers real-world Downloads/Desktop/Documents
    /// nesting.
    public var maxDepth: Int

    /// Whether to walk into dotfiles/dot-directories. `false` by default —
    /// hidden files in these user-facing directories are almost always
    /// app-managed state (`.DS_Store`, sync-client metadata, ...) rather
    /// than user media the person would think to look for here.
    public var includeHiddenFiles: Bool

    public init(
        minimumSizeBytes: Int64 = defaultMinimumSizeBytes,
        minimumAgeDays: Int? = defaultMinimumAgeDays,
        fileTypeFilter: Set<LargeOldFileTypeCategory>? = nil,
        scopedDirectories: [String] = defaultScopedDirectories,
        skippedDirectoryNames: Set<String> = defaultSkippedDirectoryNames,
        skippedDirectoryExtensions: Set<String> = defaultSkippedDirectoryExtensions,
        maxDepth: Int = 12,
        includeHiddenFiles: Bool = false
    ) {
        self.minimumSizeBytes = minimumSizeBytes
        self.minimumAgeDays = minimumAgeDays
        self.fileTypeFilter = fileTypeFilter
        self.scopedDirectories = scopedDirectories
        self.skippedDirectoryNames = skippedDirectoryNames
        self.skippedDirectoryExtensions = skippedDirectoryExtensions
        self.maxDepth = maxDepth
        self.includeHiddenFiles = includeHiddenFiles
    }
}
