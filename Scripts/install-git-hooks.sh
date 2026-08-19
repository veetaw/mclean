#!/usr/bin/env bash
#
# Scripts/install-git-hooks.sh — OPT-IN installer for the local pre-push
# hook (Scripts/pre-push-hook.sh).
#
# Nothing in this repo runs this automatically. A maintainer runs it
# deliberately, once, to have `git push` run Scripts/ci.sh locally and
# block the push on failure:
#
#   Scripts/install-git-hooks.sh
#
# To uninstall: rm .git/hooks/pre-push

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

HOOKS_DIR="$REPO_ROOT/.git/hooks"
SOURCE_HOOK="$REPO_ROOT/Scripts/pre-push-hook.sh"
TARGET_HOOK="$HOOKS_DIR/pre-push"

if [ ! -d "$REPO_ROOT/.git" ]; then
  echo "No .git directory found at $REPO_ROOT — is this a git repo?" >&2
  exit 1
fi

if [ ! -f "$SOURCE_HOOK" ]; then
  echo "Cannot find $SOURCE_HOOK" >&2
  exit 1
fi

if [ -e "$TARGET_HOOK" ] && [ ! -L "$TARGET_HOOK" ]; then
  echo "$TARGET_HOOK already exists and is not a symlink we manage." >&2
  echo "Remove or back it up first, then re-run this installer." >&2
  exit 1
fi

ln -sf "$SOURCE_HOOK" "$TARGET_HOOK"
chmod +x "$SOURCE_HOOK" "$TARGET_HOOK"

echo "Installed: $TARGET_HOOK -> $SOURCE_HOOK"
echo "From now on, 'git push' will run Scripts/ci.sh first and block the"
echo "push if it fails. Bypass once with: git push --no-verify"
echo "Uninstall any time with: rm $TARGET_HOOK"
