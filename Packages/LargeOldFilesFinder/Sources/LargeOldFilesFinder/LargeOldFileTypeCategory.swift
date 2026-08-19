import Foundation

/// Broad file-type buckets `LargeOldFilesFinder` can optionally restrict
/// itself to via `LargeOldFilesFinderConfig.fileTypeFilter`. A `nil` filter
/// (the default) means no type restriction — any file matching the
/// size/age thresholds qualifies regardless of extension.
///
/// This is a small, hand-maintained extension table rather than a
/// `UTType`-based classification. `UTType` would give richer, more accurate
/// coverage (including files with no/unusual extensions), but pulling in
/// `UniformTypeIdentifiers` for a same-package, extension-based filter is
/// more machinery than this finder currently needs; documented here as a
/// reasonable follow-up if finer-grained type detection is ever required.
public enum LargeOldFileTypeCategory: String, Sendable, Codable, CaseIterable, Hashable {
    case video
    case archive
    case diskImage
    case image
    case audio
    case document

    /// Lowercased file extensions (without the leading dot) belonging to
    /// this category. Deliberately common/representative, not exhaustive.
    var extensions: Set<String> {
        switch self {
        case .video:
            return ["mov", "mp4", "m4v", "avi", "mkv", "wmv", "flv", "mpg", "mpeg", "webm"]
        case .archive:
            return ["zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz", "zst", "pkg"]
        case .diskImage:
            return ["dmg", "iso", "img", "toast", "sparseimage", "sparsebundle", "cdr"]
        case .image:
            return ["jpg", "jpeg", "png", "heic", "heif", "tiff", "tif", "bmp", "gif", "raw", "cr2", "nef", "arw", "psd"]
        case .audio:
            return ["mp3", "wav", "aac", "flac", "m4a", "aiff", "aif", "ogg"]
        case .document:
            return ["pdf", "doc", "docx", "ppt", "pptx", "xls", "xlsx", "key", "numbers", "pages"]
        }
    }

    /// Every category (if any) whose extension list contains `ext`
    /// (case-insensitive, leading dot optional). A given extension can, in
    /// principle, belong to more than one category — none currently overlap,
    /// but callers should not assume exactly one match.
    static func categories(matchingExtension ext: String) -> Set<LargeOldFileTypeCategory> {
        let lower = ext.lowercased()
        guard !lower.isEmpty else { return [] }
        return Set(LargeOldFileTypeCategory.allCases.filter { $0.extensions.contains(lower) })
    }
}
