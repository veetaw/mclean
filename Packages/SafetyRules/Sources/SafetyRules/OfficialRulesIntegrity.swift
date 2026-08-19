import Foundation

/// The expected SHA-256 of `Resources/official_rules.yaml`, embedded in the
/// binary — checkpoint 4: "calcola lo SHA-256 di official_rules.yaml e
/// confrontalo con un hash atteso embeddato nel binario (aggiornato ad ogni
/// release)". `RuleFileLoader` compares the on-disk bundled file's actual
/// hash against this constant at load time. This is a corruption/tamper
/// *detector*, not a cryptographic signature — good enough to catch "file
/// was modified by something other than an app update", explicitly not
/// meant to defend against a sophisticated attacker who can also patch the
/// binary (checkpoint 4: "Nessuna firma crittografica complessa per ora").
///
/// **Keep this in sync with `Resources/official_rules.yaml`.** Whenever
/// that file changes, regenerate this constant with:
///
/// ```sh
/// Scripts/update-official-rules-hash.sh
/// ```
public enum OfficialRulesIntegrity {
    public static let expectedSHA256Hex = "10254c706011581e01df391cfc5489a2f87e630319e07bcd7aa528bfe12d40f0"
}
