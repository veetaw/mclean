#!/usr/bin/env bash
#
# Scripts/ci.sh — Track A local CI: generate, build, test.
#
# Runs, in order:
#   1. `xcodegen generate` in App/
#   2. `xcodebuild build` for MCleanPro-DeveloperID (Debug)
#   3. `swift test` for every package under Packages/*/
#
# Scope note: only MCleanPro-DeveloperID is built/tested here.
# MCleanPro-AppStore is deliberately paused from the active build/test
# pipeline (the user's own choice, to save time/tokens) — its code,
# Capabilities gating, entitlements, banner, and App/project.yml scheme all
# stay in the repo untouched and buildable on demand later via the manual
# commands in README.md. It is not broken or missing; it's just out of
# scope for this script. See ARCHITECTURE.md / README.md.
#
# This script deliberately does NOT bail out on the first failure the way a
# bare `set -e` script would. It runs every step it reasonably can, records
# what passed/failed as it goes, and prints a summary at the end naming
# exactly which step(s) broke — then exits non-zero if anything failed.
# Every fallible command below is wrapped in an `if`, which is the standard
# way to keep a command from tripping `set -e` while still using it for
# everything else (a stray typo, a bad `cd`, etc. still aborts immediately).
#
# Usage:
#   Scripts/ci.sh
#
# Runnable from any working directory; safe to run repeatedly (xcodegen
# regeneration and `swift test` are both idempotent).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

SCHEME="MCleanPro-DeveloperID"
CONFIGURATION="Debug"
XCODEPROJ="App/MCleanPro.xcodeproj"
DERIVED_DATA_PATH="$REPO_ROOT/.build/DerivedData"

# Plain-string accumulators instead of bash arrays: the macOS system /bin/bash
# is still 3.2, where `set -u` + expanding an empty array is unreliable.
# Newline-separated strings sidestep that entirely.
PASSED=""
FAILED=""

record_pass() { PASSED="${PASSED}${1}"$'\n'; }
record_fail() { FAILED="${FAILED}${1}"$'\n'; }

step() {
  echo ""
  echo "==> $1"
}

# --- Step 1: xcodegen generate --------------------------------------------
step "xcodegen generate (App/)"
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen not found on PATH. Install with: brew install xcodegen" >&2
  record_fail "xcodegen generate (xcodegen not installed — see README.md)"
elif (cd App && xcodegen generate); then
  record_pass "xcodegen generate"
else
  record_fail "xcodegen generate"
fi

# --- Step 2: xcodebuild build MCleanPro-DeveloperID (Debug) ---------------
# Only attempted if xcodegen actually produced a project — building against
# a stale/missing .xcodeproj would just produce a confusing secondary
# failure on top of the real one.
if [ -d "$XCODEPROJ" ]; then
  step "xcodebuild build $SCHEME ($CONFIGURATION)"
  if xcodebuild \
      -project "$XCODEPROJ" \
      -scheme "$SCHEME" \
      -configuration "$CONFIGURATION" \
      -destination "platform=macOS" \
      -derivedDataPath "$DERIVED_DATA_PATH" \
      build; then
    record_pass "xcodebuild build $SCHEME ($CONFIGURATION)"
  else
    record_fail "xcodebuild build $SCHEME ($CONFIGURATION)"
  fi
else
  step "xcodebuild build $SCHEME ($CONFIGURATION)"
  echo "Skipping: $XCODEPROJ not found (xcodegen generate must have failed above)." >&2
  record_fail "xcodebuild build $SCHEME ($CONFIGURATION) [skipped: no .xcodeproj]"
fi

# --- Step 3: swift test for every package ----------------------------------
# Same loop shape TESTING.md documents: `for pkg in Packages/*/; do (cd "$pkg" && swift test); done`
step "swift test (Packages/*/)"
for pkg in Packages/*/; do
  pkg_name="$(basename "$pkg")"
  echo ""
  echo "--> swift test: $pkg_name"
  if (cd "$pkg" && swift test); then
    record_pass "swift test: $pkg_name"
  else
    record_fail "swift test: $pkg_name"
  fi
done

# --- Summary -----------------------------------------------------------
echo ""
echo "================================================================"
echo "CI SUMMARY"
echo "================================================================"
if [ -n "$PASSED" ]; then
  echo "Passed:"
  echo "$PASSED" | sed '/^$/d' | sed 's/^/  OK    /'
fi
if [ -n "$FAILED" ]; then
  echo ""
  echo "Failed:"
  echo "$FAILED" | sed '/^$/d' | sed 's/^/  FAIL  /'
  echo "================================================================"
  exit 1
fi
echo "================================================================"
echo "All checks passed (MCleanPro-DeveloperID build + every package's tests)."
exit 0
