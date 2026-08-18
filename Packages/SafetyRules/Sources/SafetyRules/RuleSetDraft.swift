import Foundation

/// ⚠️ DRAFT — PENDING USER REVIEW (PROMPT MASTER §10 checkpoint 4).
///
/// Proposed shape for the versioned, user-inspectable rule file described in
/// SAFETY_RULES.md. Nothing in the app loads or trusts this format yet; it
/// exists so the shape can be reviewed before it's finalized. Do not wire
/// this up to any deletion path before that review happens.
///
/// Rationale for the shape below:
/// - `id` is a stable dotted string (matches `Detector.id` style) so a rule
///   can be referenced from `SafetyVerdict` and from user overrides/logs.
/// - `classification` is intentionally the same three-way split as
///   `SafetyVerdict` (forbidden / safeAuto / needsConfirmation) so the file
///   format can't express anything the type system doesn't already model.
/// - `match` is deliberately narrow (path glob + optional min-age) rather
///   than a general expression language, to keep the file auditable by a
///   non-programmer user.
public struct SafetyRuleDraft: Sendable, Hashable, Codable {
    public enum Classification: String, Sendable, Codable {
        case safeAuto = "safe-auto"
        case needsConfirmation = "needs-confirmation"
        // Note: "forbidden" is deliberately NOT expressible here — the
        // hardcoded `Denylist` is the only source of forbidden rules, by
        // design (PROMPT MASTER §2: "non bypassabile da UI").
    }

    public struct Match: Sendable, Hashable, Codable {
        /// Glob relative to a well-known root, e.g. "~/Library/Caches/**".
        public var pathGlob: String
        /// Only match items whose best `LastUsedEvidence.date` is at least
        /// this many days in the past. `nil` means no age requirement.
        public var minimumAgeDays: Int?
    }

    public var id: String
    public var description: String
    public var classification: Classification
    public var match: Match
    /// Schema/document version this rule was authored against, so future
    /// migrations can detect stale rule files. See `RuleFileDraft.version`.
    public var introducedInVersion: Int
}

/// Top-level document shape: a version stamp (for migrations) plus the list
/// of rules. Proposed on-disk format is YAML for human editability; JSON
/// Schema companion file would be generated from this struct for validation.
public struct RuleFileDraft: Sendable, Hashable, Codable {
    public var version: Int
    public var rules: [SafetyRuleDraft]
}
