import Foundation

/// Finalized shape of the versioned, user-inspectable rule file (checkpoint
/// 4 — closed; see ARCHITECTURE.md's decisions log). Two files are loaded
/// and merged at runtime by `RuleFileLoader`:
///
/// - **Official rules** — shipped read-only inside the app bundle
///   (`Resources/official_rules.yaml`), integrity-checked against an
///   expected hash (`OfficialRulesIntegrity`). Overwritten by app updates.
/// - **User rules** — `~/Library/Application Support/MCleanPro/user_rules.yaml`,
///   created empty (with example comments) on first run if absent, never
///   touched by an app update.
///
/// Rationale for the shape below:
/// - `id` is a stable dotted string (matches `Detector.id` style) so a rule
///   can be referenced from `SafetyVerdict` and from logs.
/// - `classification` is intentionally narrower than `SafetyVerdict` — it
///   can only be `safe-auto` or `needs-confirmation`. `forbidden` is
///   deliberately NOT expressible here: the hardcoded `Denylist` is the
///   only source of forbidden classifications, by design (PROMPT MASTER
///   §2: "non bypassabile da UI"), so neither this file nor a maliciously
///   edited copy of it can ever grant access to a protected path.
/// - `match` is deliberately narrow (path glob + optional min-age) rather
///   than a general expression language, to keep the file auditable by a
///   non-programmer user.
public struct SafetyRule: Sendable, Hashable, Codable {
    public enum Classification: String, Sendable, Codable {
        case safeAuto = "safe-auto"
        case needsConfirmation = "needs-confirmation"
    }

    public struct Match: Sendable, Hashable, Codable {
        /// Glob pattern matched against `ScanItem.path`. `*` matches any
        /// run of characters within one path component; `**` matches
        /// across component boundaries (any depth). See `GlobMatcher`.
        public var pathGlob: String
        /// Only match items whose best `LastUsedEvidence.date` is at least
        /// this many days in the past. `nil` means no age requirement. An
        /// item with no `lastUsed` evidence at all never satisfies an
        /// age requirement (fails closed, not open).
        public var minimumAgeDays: Int?

        public init(pathGlob: String, minimumAgeDays: Int? = nil) {
            self.pathGlob = pathGlob
            self.minimumAgeDays = minimumAgeDays
        }
    }

    public var id: String
    public var description: String
    public var classification: Classification
    public var match: Match
    /// Schema/document version this rule was authored against, so future
    /// migrations can detect stale rule files. See `RuleFile.version`.
    public var introducedInVersion: Int

    public init(
        id: String,
        description: String,
        classification: Classification,
        match: Match,
        introducedInVersion: Int
    ) {
        self.id = id
        self.description = description
        self.classification = classification
        self.match = match
        self.introducedInVersion = introducedInVersion
    }
}

/// Top-level document shape: a version stamp (for migrations) plus the
/// list of rules. On-disk format is YAML, parsed via Yams, for human
/// editability.
public struct RuleFile: Sendable, Hashable, Codable {
    public var version: Int
    public var rules: [SafetyRule]

    public init(version: Int, rules: [SafetyRule]) {
        self.version = version
        self.rules = rules
    }
}

/// Which file a loaded rule came from — determines how it's treated on an
/// official-rules integrity failure (see `RuleFileLoader`): official
/// safe-auto rules are disabled on a hash mismatch, user safe-auto rules
/// are not (the user's own file isn't subject to the "shipped, therefore
/// verifiable against a known-good hash" argument — it's inherently
/// user-authored and trusted the same way any of the user's own local
/// settings are).
public enum RuleSource: String, Sendable, Hashable, Codable {
    case official
    case user
}

/// A rule plus which file it came from.
public struct SourcedRule: Sendable, Hashable {
    public let rule: SafetyRule
    public let source: RuleSource

    public init(rule: SafetyRule, source: RuleSource) {
        self.rule = rule
        self.source = source
    }
}
