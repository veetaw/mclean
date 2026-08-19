import Foundation
import CoreScanEngine

/// Flags `.lproj` language-resource directories inside installed
/// `/Applications/*.app` bundles for locales that don't match any of the
/// user's preferred languages.
///
/// **Deliberately narrow scope** — this is the riskiest sub-area of this
/// package, since removing the wrong `.lproj` can break an app's UI:
/// - Only looks at `Contents/Resources/*.lproj` directly inside each
///   top-level `/Applications/*.app` bundle — never descends into nested
///   frameworks, plugins, or helper bundles, where a mistake is both more
///   likely and harder to reason about from outside.
/// - `Base.lproj` is always skipped. Many apps ship their actual UI strings
///   there and use per-locale `.lproj` directories only for translated
///   string tables layered on top — removing `Base.lproj` can break the
///   app's UI entirely, not just its localization.
/// - Any locale whose primary language subtag is `en` (`en.lproj`,
///   `en_GB.lproj`, `English.lproj`, ...) is always skipped, as a safe
///   fallback, regardless of the user's preferred languages.
/// - Matching against preferred languages compares *primary language
///   subtags only* (e.g. `"it"` extracted from both `it.lproj` and the
///   preferred-language tag `"it-IT"`), not exact string equality — an
///   exact match would under-count and risk flagging, e.g., `pt.lproj` for
///   a user whose preferred tag is `"pt-BR"` rather than plain `"pt"`.
/// - Reason text is deliberately hedged ("review before removing"), unlike
///   this package's other detectors that describe well-understood
///   regenerable caches as safe to clear: a locale unused by *this* user's
///   preferred-language list may still be needed by a different macOS user
///   account on a shared Mac, which this detector has no way to observe.
///
/// Strictly read-only. See `CoreScanEngine.Detector`.
public struct LanguagePackDetector: Detector {
    public let id = "junk.languagepacks.unused-lproj"
    public let displayName = "Unused language packs"
    public let category: DetectorCategory = .systemJunk

    private let applicationsRootPath: String
    private let preferredLanguages: [String]

    /// - Parameters:
    ///   - applicationsRootPath: defaults to `/Applications`. Not
    ///     home-relative, so — like `TempFilesDetector`'s system temp
    ///     directory — it isn't resolved from `ScanContext.roots`; tests
    ///     override it directly to point at a throwaway directory tree
    ///     shaped like `/Applications`.
    ///   - preferredLanguages: defaults to `Locale.preferredLanguages`, the
    ///     user's actual System Settings > General > Language & Region
    ///     order. Tests override it to exercise matching logic
    ///     deterministically, independent of the machine running the test.
    public init(
        applicationsRootPath: String = "/Applications",
        preferredLanguages: [String] = Locale.preferredLanguages
    ) {
        self.applicationsRootPath = applicationsRootPath
        self.preferredLanguages = preferredLanguages
    }

    public func scan(context: ScanContext) async throws -> [ScanItem] {
        guard CacheCleanerFS.isDirectory(applicationsRootPath) else { return [] }

        let preferredPrimaryCodes = Set(preferredLanguages.compactMap(Self.primaryLanguageCode(from:)))
        var items: [ScanItem] = []

        for appEntry in CacheCleanerFS.directoryEntries(applicationsRootPath) {
            if Task.isCancelled { break }
            guard appEntry.hasSuffix(".app") else { continue }
            let resourcesPath = applicationsRootPath + "/" + appEntry + "/Contents/Resources"
            guard CacheCleanerFS.isDirectory(resourcesPath) else { continue }

            for lprojEntry in CacheCleanerFS.directoryEntries(resourcesPath) {
                if Task.isCancelled { break }
                guard lprojEntry.hasSuffix(".lproj") else { continue }
                let localeCode = String(lprojEntry.dropLast(".lproj".count))
                guard localeCode != "Base" else { continue }
                guard let primary = Self.primaryLanguageCode(from: localeCode), primary != "en" else { continue }
                guard !preferredPrimaryCodes.contains(primary) else { continue }

                let path = resourcesPath + "/" + lprojEntry
                let size = CacheCleanerFS.recursiveSize(of: path, isCancelled: { Task.isCancelled })

                items.append(ScanItem(
                    path: path,
                    sizeBytes: size,
                    sourceDetectorID: id,
                    category: "Unused language pack — \(appEntry)",
                    lastUsed: nil,
                    reason: "'\(lprojEntry)' inside \(appEntry) ships localized resources for '\(localeCode)', which doesn't match any of your preferred languages (\(preferredLanguages.joined(separator: ", "))). English/Base resources are always kept as a fallback and never flagged. Review before removing — a locale unused by your account may still be needed by another user on a shared Mac."
                ))
            }
        }
        return items
    }

    /// Extracts the primary language subtag from a locale-ish string —
    /// `"it-IT"`, `"it_IT"`, and `"it"` all yield `"it"`. Returns `nil` for
    /// an empty string.
    static func primaryLanguageCode(from raw: String) -> String? {
        let lowered = raw.lowercased()
        let separators = CharacterSet(charactersIn: "-_")
        guard let primary = lowered.components(separatedBy: separators).first, !primary.isEmpty else { return nil }
        return primary
    }
}
