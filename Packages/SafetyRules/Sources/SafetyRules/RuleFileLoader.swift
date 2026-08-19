import CryptoKit
import Foundation
import Yams

/// Result of loading + merging the official and user rule files.
public struct LoadedRuleSet: Sendable {
    public let rules: [SourcedRule]
    /// `false` if `official_rules.yaml`'s hash didn't match
    /// `OfficialRulesIntegrity.expectedSHA256Hex` — see `RuleFileLoader`.
    public let officialRulesIntegrityOK: Bool
    /// Non-nil, human-readable text for a Settings-screen warning banner
    /// whenever `officialRulesIntegrityOK` is `false`, or a rule file
    /// failed to parse. `nil` when everything loaded cleanly.
    public let warning: String?

    public static let empty = LoadedRuleSet(rules: [], officialRulesIntegrityOK: true, warning: nil)
}

/// Loads, verifies, and merges the official (bundled) and user
/// (`~/Library/Application Support/MCleanPro/user_rules.yaml`) rule files —
/// checkpoint 4's closed decision on where rules live. See
/// `SAFETY_RULES.md` and `ARCHITECTURE.md`'s decisions log.
public enum RuleFileLoader {
    /// - Parameter userRulesDirectory: defaults to
    ///   `~/Library/Application Support/MCleanPro`; tests inject a temp
    ///   directory instead.
    public static func load(
        userRulesDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) -> LoadedRuleSet {
        // `Bundle.module` is package-internal (SwiftPM generates it without
        // `public`), so it can't appear as a public default-argument value
        // directly — passed explicitly here instead, in the function body.
        load(userRulesDirectory: userRulesDirectory, bundle: Bundle.module, fileManager: fileManager)
    }

    /// Same as above, with an injectable bundle — used by tests to exercise
    /// a missing/corrupt official file without touching the real one.
    static func load(
        userRulesDirectory: URL?,
        bundle: Bundle,
        fileManager: FileManager = .default
    ) -> LoadedRuleSet {
        var warnings: [String] = []

        let (officialRules, officialIntegrityOK) = loadOfficialRules(bundle: bundle, warnings: &warnings)

        let userDirectory = userRulesDirectory ?? Self.defaultUserRulesDirectory(fileManager: fileManager)
        let userRules = loadOrCreateUserRules(directory: userDirectory, fileManager: fileManager, warnings: &warnings)

        let merged = officialRules.map { SourcedRule(rule: $0, source: .official) }
            + userRules.map { SourcedRule(rule: $0, source: .user) }

        return LoadedRuleSet(
            rules: merged,
            officialRulesIntegrityOK: officialIntegrityOK,
            warning: warnings.isEmpty ? nil : warnings.joined(separator: " ")
        )
    }

    public static func defaultUserRulesDirectory(fileManager: FileManager = .default) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return appSupport.appendingPathComponent("MCleanPro", isDirectory: true)
    }

    // MARK: - Official rules

    private static func loadOfficialRules(bundle: Bundle, warnings: inout [String]) -> ([SafetyRule], Bool) {
        guard let url = bundle.url(forResource: "official_rules", withExtension: "yaml") else {
            warnings.append("official_rules.yaml is missing from the app bundle — no official rules loaded.")
            return ([], false)
        }
        guard let data = try? Data(contentsOf: url) else {
            warnings.append("official_rules.yaml could not be read — no official rules loaded.")
            return ([], false)
        }

        let actualHash = sha256Hex(of: data)
        let integrityOK = actualHash == OfficialRulesIntegrity.expectedSHA256Hex

        guard let text = String(data: data, encoding: .utf8) else {
            warnings.append("official_rules.yaml is not valid UTF-8 — no official rules loaded.")
            return ([], false)
        }

        guard let ruleFile = try? parseRuleFile(text) else {
            warnings.append("official_rules.yaml failed to parse — no official rules loaded.")
            return ([], integrityOK)
        }

        if !integrityOK {
            warnings.append(
                "official_rules.yaml's contents don't match what shipped with this version of the app "
                + "(hash mismatch). Every official safe-auto rule is disabled until this is resolved "
                + "(e.g. by reinstalling); needs-confirmation rules are unaffected, and your own "
                + "user_rules.yaml is unaffected."
            )
        }

        // A hash mismatch disables official safe-auto rules specifically
        // (downgrading them to needs-confirmation) rather than discarding
        // the whole file — a tampered/corrupted official file might still
        // contain perfectly good needs-confirmation guidance, and
        // needs-confirmation is never a safety risk to keep trusting.
        let rules = integrityOK ? ruleFile.rules : ruleFile.rules.map { rule in
            var downgraded = rule
            downgraded.classification = .needsConfirmation
            return downgraded
        }

        return (rules, integrityOK)
    }

    // MARK: - User rules

    private static let userRulesTemplate = """
    # MClean Pro — your personal safety rules.
    #
    # This file is yours: MClean Pro never overwrites it (app updates only
    # touch the bundled official_rules.yaml). Add entries below to mark your
    # own paths as safe-auto (cleaned without a per-item prompt, but still
    # quarantined first) or needs-confirmation (the default for everything
    # not covered by a rule).
    #
    # classification can only be "safe-auto" or "needs-confirmation" — never
    # "forbidden". The hardcoded denylist (system paths, credential
    # directories, files matching .env/*.pem/*.key, dirty git repos) can
    # never be overridden from this file or any other.
    #
    # Example (uncomment and edit to use):
    #
    # version: 1
    # rules:
    #   - id: user.my-scratch-dir
    #     description: "My personal scratch directory — always safe to clean"
    #     classification: safe-auto
    #     match:
    #       pathGlob: "/Users/me/Scratch/**"
    #       minimumAgeDays: 7
    #     introducedInVersion: 1

    version: 1
    rules: []
    """

    private static func loadOrCreateUserRules(
        directory: URL,
        fileManager: FileManager,
        warnings: inout [String]
    ) -> [SafetyRule] {
        let fileURL = directory.appendingPathComponent("user_rules.yaml")

        if !fileManager.fileExists(atPath: fileURL.path) {
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
                try userRulesTemplate.write(to: fileURL, atomically: true, encoding: .utf8)
            } catch {
                warnings.append("Couldn't create user_rules.yaml (\(error.localizedDescription)) — no user rules loaded.")
            }
            return [] // freshly created from the template, which has an empty rule list
        }

        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
            warnings.append("user_rules.yaml could not be read — no user rules loaded.")
            return []
        }

        guard let ruleFile = try? parseRuleFile(text) else {
            warnings.append("user_rules.yaml failed to parse — check its YAML syntax. No user rules loaded until it's fixed.")
            return []
        }

        return ruleFile.rules
    }

    // MARK: - Shared parsing/hashing

    private static func parseRuleFile(_ text: String) throws -> RuleFile {
        let decoder = YAMLDecoder()
        return try decoder.decode(RuleFile.self, from: text)
    }

    static func sha256Hex(of data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
