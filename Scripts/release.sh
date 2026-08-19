#!/usr/bin/env bash
#
# Scripts/release.sh — Track A local release packaging.
#
# What this script does, in order:
#   1. Reads the current version from the latest `vX.Y.Z` git tag (falls
#      back to v0.1.0 if no tag exists yet — see Scripts/README.md).
#   2. Bumps it (patch/minor/major, given as an explicit CLI argument).
#   3. Regenerates CHANGELOG.md from Conventional Commit messages since the
#      last tag.
#   4. Builds MCleanPro-DeveloperID in Release configuration.
#   5. Packages the built .app into a .dmg (hdiutil, always available;
#      prefers `create-dmg` when it happens to be installed).
#   6. Inspects the actual code-signing identity used and names the .dmg
#      honestly: only a real "Developer ID Application" signature drops the
#      "-unsigned-local-build-only" suffix.
#
# Scope note: only MCleanPro-DeveloperID is built/packaged here.
# MCleanPro-AppStore is deliberately paused from the active pipeline (the
# user's own choice, to save time/tokens) — it stays in the repo, untouched
# and buildable on demand, it's just not part of this release flow.
#
# What this script deliberately does NOT do:
#   - It never runs `git push`, never uploads or publishes anything, and
#     makes no network calls of any kind. Its job ends at producing a local
#     .dmg in dist/.
#   - It never creates a git tag or commit on your behalf. It prints the
#     exact commands to run yourself once you've reviewed CHANGELOG.md and
#     the built .dmg — tagging a release is a deliberate human action.
#
# Usage:
#   Scripts/release.sh patch   # 0.1.0 -> 0.1.1
#   Scripts/release.sh minor   # 0.1.0 -> 0.2.0
#   Scripts/release.sh major   # 0.1.0 -> 1.0.0
#
# Version-bump strategy: explicit CLI argument, not automatic inference
# from commit types. This is a deliberate, simpler choice (see
# Scripts/README.md for the trade-off) — you decide what kind of release
# this is, the script just does the arithmetic and the packaging.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

SCHEME="MCleanPro-DeveloperID"
CONFIGURATION="Release"
XCODEPROJ="App/MCleanPro.xcodeproj"
DERIVED_DATA_PATH="$REPO_ROOT/.build/DerivedData-Release"
DIST_DIR="$REPO_ROOT/dist"
CHANGELOG_FILE="$REPO_ROOT/CHANGELOG.md"

usage() {
  echo "Usage: $(basename "${BASH_SOURCE[0]}") <patch|minor|major>" >&2
  echo "" >&2
  echo "Bumps the version tracked by git tags (vX.Y.Z), regenerates" >&2
  echo "CHANGELOG.md, builds MCleanPro-DeveloperID (Release), and packages" >&2
  echo "it into a .dmg under dist/. Never pushes or publishes anything." >&2
}

if [ "${1:-}" = "" ]; then
  usage
  exit 1
fi
BUMP_TYPE="$1"
case "$BUMP_TYPE" in
  patch|minor|major) ;;
  -h|--help) usage; exit 0 ;;
  *) echo "Unknown bump type: $BUMP_TYPE" >&2; usage; exit 1 ;;
esac

echo "==> Determining current version"

# Latest vX.Y.Z tag, sorted by semver. `git tag -l` with a glob never errors
# on an empty repo/no matches, it just prints nothing.
LAST_TAG="$(git tag -l 'v[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname | head -n 1)"

if [ -z "$LAST_TAG" ]; then
  # Documented fallback: no vX.Y.Z tag exists yet in this repo. v0.1.0 is
  # treated as the pre-release baseline so the very first release this
  # script produces is v0.1.1/v0.2.0/v1.0.0 depending on the bump argument.
  # See Scripts/README.md for how a maintainer creates the actual v0.1.0
  # tag on their own — this script does not create it for you.
  CURRENT_VERSION="0.1.0"
  COMMIT_RANGE=""
  RANGE_DESC="all commits (no vX.Y.Z tag exists yet — using v$CURRENT_VERSION as the baseline)"
  echo "    No existing vX.Y.Z tag found. Using fallback baseline v$CURRENT_VERSION."
else
  CURRENT_VERSION="${LAST_TAG#v}"
  COMMIT_RANGE="${LAST_TAG}..HEAD"
  RANGE_DESC="$COMMIT_RANGE"
  echo "    Latest tag: $LAST_TAG"
fi

IFS='.' read -r CUR_MAJOR CUR_MINOR CUR_PATCH <<< "$CURRENT_VERSION"

case "$BUMP_TYPE" in
  major) NEW_MAJOR=$((CUR_MAJOR + 1)); NEW_MINOR=0; NEW_PATCH=0 ;;
  minor) NEW_MAJOR=$CUR_MAJOR; NEW_MINOR=$((CUR_MINOR + 1)); NEW_PATCH=0 ;;
  patch) NEW_MAJOR=$CUR_MAJOR; NEW_MINOR=$CUR_MINOR; NEW_PATCH=$((CUR_PATCH + 1)) ;;
esac
NEW_VERSION="${NEW_MAJOR}.${NEW_MINOR}.${NEW_PATCH}"

echo "    Current: v$CURRENT_VERSION -> New: v$NEW_VERSION ($BUMP_TYPE)"

# ---------------------------------------------------------------------------
# CHANGELOG.md generation
# ---------------------------------------------------------------------------
echo ""
echo "==> Generating CHANGELOG.md entry for v$NEW_VERSION (commits: $RANGE_DESC)"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# One file per Conventional Commit type; anything that doesn't match the
# `type(scope)!: subject` shape falls into "other.txt" rather than being
# silently dropped.
for t in feat fix docs style refactor perf test build ci chore revert other breaking; do
  : > "$TMP_DIR/$t.txt"
done

if [ -z "$COMMIT_RANGE" ]; then
  git log --pretty=format:'%H' > "$TMP_DIR/hashes.txt"
else
  git log "$COMMIT_RANGE" --pretty=format:'%H' > "$TMP_DIR/hashes.txt"
fi

COMMIT_COUNT=0
while IFS= read -r hash; do
  [ -z "$hash" ] && continue
  COMMIT_COUNT=$((COMMIT_COUNT + 1))
  subject="$(git log -1 --pretty=format:'%s' "$hash")"
  body="$(git log -1 --pretty=format:'%b' "$hash")"
  short="$(git rev-parse --short "$hash")"

  if printf '%s\n' "$subject" | grep -qE '^[a-zA-Z]+(\([^)]*\))?!:'; then
    echo "- $subject ($short)" >> "$TMP_DIR/breaking.txt"
  elif printf '%s\n' "$body" | grep -q 'BREAKING CHANGE'; then
    echo "- $subject ($short)" >> "$TMP_DIR/breaking.txt"
  fi

  type_raw="$(printf '%s\n' "$subject" | sed -nE 's/^([a-zA-Z]+)(\([^)]*\))?!?:.*/\1/p')"
  type_lower="$(printf '%s' "$type_raw" | tr '[:upper:]' '[:lower:]')"

  case "$type_lower" in
    feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)
      echo "- $subject ($short)" >> "$TMP_DIR/$type_lower.txt"
      ;;
    *)
      echo "- $subject ($short)" >> "$TMP_DIR/other.txt"
      ;;
  esac
done < "$TMP_DIR/hashes.txt"

echo "    $COMMIT_COUNT commit(s) since $RANGE_DESC"

{
  echo "## v$NEW_VERSION - $(date +%Y-%m-%d)"
  echo ""
  if [ -s "$TMP_DIR/breaking.txt" ]; then
    echo "### Breaking Changes"
    echo ""
    cat "$TMP_DIR/breaking.txt"
    echo ""
  fi
  print_section() {
    local file="$1" heading="$2"
    if [ -s "$file" ]; then
      echo "### $heading"
      echo ""
      cat "$file"
      echo ""
    fi
  }
  print_section "$TMP_DIR/feat.txt" "Features"
  print_section "$TMP_DIR/fix.txt" "Bug Fixes"
  print_section "$TMP_DIR/refactor.txt" "Refactoring"
  print_section "$TMP_DIR/perf.txt" "Performance"
  print_section "$TMP_DIR/docs.txt" "Documentation"
  print_section "$TMP_DIR/test.txt" "Tests"
  print_section "$TMP_DIR/build.txt" "Build"
  print_section "$TMP_DIR/ci.txt" "CI"
  print_section "$TMP_DIR/chore.txt" "Chores"
  print_section "$TMP_DIR/revert.txt" "Reverts"
  print_section "$TMP_DIR/other.txt" "Other"
} > "$TMP_DIR/new_entry.md"

if [ -f "$CHANGELOG_FILE" ]; then
  cat "$TMP_DIR/new_entry.md" "$CHANGELOG_FILE" > "$TMP_DIR/changelog_combined.md"
else
  {
    echo "# Changelog"
    echo ""
    echo "All notable changes to this project, grouped by Conventional Commit"
    echo "type and generated by Scripts/release.sh. See Scripts/README.md."
    echo ""
    cat "$TMP_DIR/new_entry.md"
  } > "$TMP_DIR/changelog_combined.md"
fi
mv "$TMP_DIR/changelog_combined.md" "$CHANGELOG_FILE"
echo "    Wrote entry to $CHANGELOG_FILE (not committed — review and commit yourself)"

# ---------------------------------------------------------------------------
# Build (Release)
# ---------------------------------------------------------------------------
echo ""
echo "==> xcodegen generate (App/)"
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen not found on PATH. Install with: brew install xcodegen" >&2
  exit 1
fi
(cd App && xcodegen generate)

echo ""
echo "==> xcodebuild build $SCHEME ($CONFIGURATION)"
if ! xcodebuild \
    -project "$XCODEPROJ" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "platform=macOS" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    build; then
  echo "" >&2
  echo "ERROR: xcodebuild failed — no package produced." >&2
  exit 1
fi

APP_PATH="$(find "$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION" -maxdepth 1 -name '*.app' | head -n 1)"
if [ -z "$APP_PATH" ]; then
  echo "" >&2
  echo "ERROR: build reported success but no .app was found under:" >&2
  echo "  $DERIVED_DATA_PATH/Build/Products/$CONFIGURATION" >&2
  exit 1
fi
echo "    Built: $APP_PATH"

# ---------------------------------------------------------------------------
# Signing check — determine what actually signed this build.
# ---------------------------------------------------------------------------
# The user has explicitly confirmed no paid Developer ID Application
# certificate exists yet (and none is needed for personal use on their own
# Mac) — so today's builds are expected to be either unsigned or signed
# with Xcode's automatic personal-team/ad-hoc signing, NOT a real
# "Developer ID Application: <Name> (<TEAMID>)" identity. We inspect the
# actual Authority chain on the built .app rather than assume — this must
# never silently produce a package that *looks* distribution-ready when it
# isn't.
echo ""
echo "==> Checking what actually signed the build"
SIGNED_WITH_DEVELOPER_ID=0
CODESIGN_OUTPUT="$(codesign -dv --verbose=4 "$APP_PATH" 2>&1 || true)"
echo "$CODESIGN_OUTPUT" | sed 's/^/    /'

if printf '%s\n' "$CODESIGN_OUTPUT" | grep -q '^Authority=Developer ID Application:'; then
  SIGNED_WITH_DEVELOPER_ID=1
  echo "    -> Signed with a real Developer ID Application certificate."
else
  echo "    -> NOT signed with a Developer ID Application certificate"
  echo "       (ad-hoc, personal-team automatic signing, or unsigned — expected today)."
fi

# ---------------------------------------------------------------------------
# Package into a .dmg
# ---------------------------------------------------------------------------
mkdir -p "$DIST_DIR"

if [ "$SIGNED_WITH_DEVELOPER_ID" = "1" ]; then
  DMG_NAME="MCleanPro-DeveloperID-v${NEW_VERSION}.dmg"
else
  DMG_NAME="MCleanPro-DeveloperID-v${NEW_VERSION}-unsigned-local-build-only.dmg"
fi
DMG_PATH="$DIST_DIR/$DMG_NAME"
rm -f "$DMG_PATH"

echo ""
echo "==> Packaging into $DMG_NAME"

STAGE_DIR="$TMP_DIR/dmg-stage"
mkdir -p "$STAGE_DIR"
cp -R "$APP_PATH" "$STAGE_DIR/"
# Drag-to-install convenience: a symlink to /Applications alongside the .app.
ln -s /Applications "$STAGE_DIR/Applications"

PACKAGED=0
if command -v create-dmg >/dev/null 2>&1; then
  echo "    create-dmg found — trying it first (falls back to hdiutil on failure)"
  if create-dmg \
      --volname "MClean Pro (Developer ID)" \
      --app-drop-link 450 150 \
      "$DMG_PATH" \
      "$STAGE_DIR" 2>&1 | sed 's/^/    /'; then
    PACKAGED=1
  else
    echo "    create-dmg failed, falling back to hdiutil." >&2
    rm -f "$DMG_PATH"
  fi
fi

if [ "$PACKAGED" = "0" ]; then
  # hdiutil is built into every Mac — this is the guaranteed path.
  if ! hdiutil create \
      -volname "MClean Pro (Developer ID)" \
      -srcfolder "$STAGE_DIR" \
      -ov -format UDZO \
      "$DMG_PATH" >/tmp/hdiutil-release-log.$$ 2>&1; then
    echo "" >&2
    echo "ERROR: hdiutil failed to create the .dmg. Output:" >&2
    cat /tmp/hdiutil-release-log.$$ >&2
    rm -f /tmp/hdiutil-release-log.$$
    exit 1
  fi
  rm -f /tmp/hdiutil-release-log.$$
  PACKAGED=1
fi

if [ ! -f "$DMG_PATH" ]; then
  echo "" >&2
  echo "ERROR: packaging reported success but $DMG_PATH does not exist." >&2
  exit 1
fi

echo ""
echo "================================================================"
if [ "$SIGNED_WITH_DEVELOPER_ID" = "1" ]; then
  echo "Packaged (Developer ID signed): $DMG_PATH"
else
  echo "Packaged as LOCAL/UNSIGNED BUILD ONLY (no Developer ID Application"
  echo "certificate was used to sign this build — see the codesign output"
  echo "above): $DMG_PATH"
fi
echo "================================================================"
echo ""
echo "This script did not commit, tag, or push anything. Next steps, if you"
echo "want to finalize this as a release:"
echo "  1. Review $CHANGELOG_FILE"
echo "  2. git add CHANGELOG.md && git commit -m \"chore(release): v$NEW_VERSION\""
echo "  3. git tag v$NEW_VERSION"
echo "  (git push is up to you — this script never pushes anything)"
