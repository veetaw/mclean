import CoreScanEngine
import Foundation

/// Default `SafetyClassifying` implementation. Checks the hardcoded
/// `Denylist` first, unconditionally — nothing below can ever override a
/// `.forbidden` verdict. Then evaluates the merged official+user rule set
/// (checkpoint 4, closed) with a **conservative merge**: if any matching
/// rule says `needsConfirmation`, that wins over any matching `safeAuto`
/// rule for the same item, regardless of which file either came from. This
/// is what makes "user rules can only add or restrict, never loosen an
/// official safety decision" (checkpoint 4) true by construction rather
/// than by convention — a user rule can add a brand-new `safeAuto` match
/// (nothing official governs), or add a stricter `needsConfirmation` match
/// that narrows an official `safeAuto` rule, but can never flip an official
/// `needsConfirmation` decision to `safeAuto`.
public struct SafetyClassifier: SafetyClassifying {
    private let rules: [SourcedRule]

    /// Non-nil when `official_rules.yaml`'s integrity check failed or a
    /// rule file failed to parse — surfaced by `MainAppUI`'s Settings
    /// screen as a visible warning (checkpoint 4). `nil` when everything
    /// loaded cleanly, or when this classifier was constructed with no
    /// rules at all (e.g. in a test).
    public let integrityWarning: String?

    /// - Parameters:
    ///   - rules: merged, sourced rules — normally produced by
    ///     `RuleFileLoader.load(...).rules`. Defaults to empty, which
    ///     makes every non-forbidden item fall back to
    ///     `needsConfirmation` — the same safe default this type had
    ///     before checkpoint 4's rule-file support existed, and still a
    ///     perfectly valid way to construct this type in a test.
    ///   - integrityWarning: normally `RuleFileLoader.load(...).warning`.
    public init(rules: [SourcedRule] = [], integrityWarning: String? = nil) {
        self.rules = rules
        self.integrityWarning = integrityWarning
    }

    /// Convenience that loads the merged official+user rule set via
    /// `RuleFileLoader` and constructs a classifier from it in one call —
    /// what `AppEnvironment` uses at startup.
    public static func loadingRules(userRulesDirectory: URL? = nil) -> SafetyClassifier {
        let loaded = RuleFileLoader.load(userRulesDirectory: userRulesDirectory)
        return SafetyClassifier(rules: loaded.rules, integrityWarning: loaded.warning)
    }

    public func classify(_ item: ScanItem) -> SafetyVerdict {
        if let reason = Denylist.forbiddenReason(forPath: item.path) {
            return .forbidden(ruleID: "denylist.path", reason: reason)
        }
        if Denylist.isLikelyBootVolumeRoot(item.path) {
            return .forbidden(ruleID: "denylist.boot-volume-root", reason: "Path is a volume root.")
        }

        let matching = rules.filter { matches($0.rule, item: item) }

        if let stricter = matching.first(where: { $0.rule.classification == .needsConfirmation }) {
            return .needsConfirmation(reason: stricter.rule.description)
        }

        if let autoMatch = matching.first(where: { $0.rule.classification == .safeAuto }) {
            if Denylist.isOnNonBootVolume(item.path) {
                return .needsConfirmation(reason: """
                \(autoMatch.rule.description) — would normally be safe-auto, but downgraded: \
                this item is on a non-boot volume, and MClean Pro never auto-cleans outside the \
                boot disk (checkpoint 4 policy).
                """)
            }
            return .safeAuto(ruleID: autoMatch.rule.id)
        }

        return .needsConfirmation(reason: "No safe-auto rule matched; default policy requires confirmation.")
    }

    private func matches(_ rule: SafetyRule, item: ScanItem) -> Bool {
        guard GlobMatcher.matches(pattern: rule.match.pathGlob, path: item.path) else { return false }

        if let minimumAgeDays = rule.match.minimumAgeDays {
            // Fails closed: an item with no last-used evidence at all never
            // satisfies an age requirement, so it can't accidentally
            // qualify for safe-auto just because we don't know its age.
            guard let lastUsedDate = item.lastUsed?.date else { return false }
            let ageDays = Calendar.current.dateComponents([.day], from: lastUsedDate, to: Date()).day ?? 0
            guard ageDays >= minimumAgeDays else { return false }
        }

        return true
    }
}
