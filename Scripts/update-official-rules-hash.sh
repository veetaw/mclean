#!/bin/sh
# Regenerates OfficialRulesIntegrity.swift's expected hash to match the
# current contents of Resources/official_rules.yaml. Run this any time you
# edit that file, and commit both changes together.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RULES_FILE="$ROOT/Packages/SafetyRules/Sources/SafetyRules/Resources/official_rules.yaml"
INTEGRITY_FILE="$ROOT/Packages/SafetyRules/Sources/SafetyRules/OfficialRulesIntegrity.swift"

HASH=$(shasum -a 256 "$RULES_FILE" | awk '{print $1}')

# Portable in-place sed (works on both BSD/macOS and GNU sed).
sed -i.bak -E "s/expectedSHA256Hex = \"[0-9a-f]+\"/expectedSHA256Hex = \"$HASH\"/" "$INTEGRITY_FILE"
rm -f "$INTEGRITY_FILE.bak"

echo "Updated expectedSHA256Hex to $HASH"
