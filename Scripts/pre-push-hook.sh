#!/usr/bin/env bash
#
# Scripts/pre-push-hook.sh — optional git pre-push hook.
#
# Runs Scripts/ci.sh before allowing a push; blocks the push (non-zero exit)
# if CI fails. NOT installed automatically by anything in this repo — see
# Scripts/install-git-hooks.sh, which a maintainer runs deliberately, once,
# to opt in.
#
# To bypass in a genuine emergency: `git push --no-verify`.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "==> pre-push hook: running Scripts/ci.sh before allowing this push"
echo "    (bypass once with: git push --no-verify)"
echo ""

if "$REPO_ROOT/Scripts/ci.sh"; then
  echo ""
  echo "==> pre-push hook: CI passed, push allowed."
  exit 0
else
  echo ""
  echo "==> pre-push hook: CI FAILED — push blocked." >&2
  echo "    Fix the failure(s) above, or bypass deliberately with:" >&2
  echo "      git push --no-verify" >&2
  exit 1
fi
