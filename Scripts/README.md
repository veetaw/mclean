# Scripts

Build / CI / release scripts. Notarization is not part of this yet — see
`ARCHITECTURE.md` and `release.sh`'s signing-check section below for why.

## Scope: MCleanPro-DeveloperID only

`ci.sh` and `release.sh` build and test **`MCleanPro-DeveloperID` only**.
`MCleanPro-AppStore` is deliberately paused from the active build/test
pipeline — this was a conscious choice (to save time/tokens while the
App Store flavor isn't the active focus), not something broken or missing.
Its code (Capabilities gating, sandbox banner, entitlements, the
`App/project.yml` scheme) stays in the repo untouched and can still be
built on demand any time with the manual commands in the root `README.md`:

```sh
cd App
xcodegen generate
xcodebuild -project MCleanPro.xcodeproj -scheme MCleanPro-AppStore -configuration Debug build
```

If App Store ever comes back into scope for automated CI/CD, add it back
into `ci.sh`/`release.sh` deliberately rather than assuming it's covered.

## `update-official-rules-hash.sh`

Unrelated to the release pipeline — regenerates the SHA-256 integrity hash
for `SafetyRules`' bundled official rule file. See the script's own header
comment and `ARCHITECTURE.md` (checkpoint 4).

## `ci.sh` — local CI

```sh
Scripts/ci.sh
```

Runnable from anywhere (it resolves its own location and `cd`s to the repo
root). Does, in order:

1. `xcodegen generate` in `App/`.
2. `xcodebuild build` for `MCleanPro-DeveloperID` (Debug).
3. `swift test` for every package under `Packages/*/`.

It does **not** stop at the first failure. It runs every step it reasonably
can (a failed `xcodegen generate` does skip the build step, since building
against a stale/missing `.xcodeproj` would just be a confusing second
failure — but every package's tests still run regardless of the build
result) and prints a summary at the end naming exactly which step(s)
failed, then exits non-zero if anything did. Nothing here runs on its own —
it only runs when you invoke it, or via the opt-in pre-push hook below.

## Git pre-push hook (opt-in)

`Scripts/pre-push-hook.sh` runs `ci.sh` and blocks `git push` if it fails.
It is **not installed automatically by anything** — install it deliberately:

```sh
Scripts/install-git-hooks.sh
```

This symlinks `Scripts/pre-push-hook.sh` to `.git/hooks/pre-push`. Bypass a
blocked push once with `git push --no-verify`; uninstall any time with
`rm .git/hooks/pre-push`.

## Conventional Commits (going forward only)

From now on, commit messages should follow
[Conventional Commits](https://www.conventionalcommits.org/):

```
<type>[optional scope][!]: <description>

[optional body]

[optional footer(s), e.g. BREAKING CHANGE: ...]
```

Common types used in this repo: `feat`, `fix`, `docs`, `chore`, `refactor`,
`test`, `build`, `ci`, `perf`, `style`, `revert`. A `!` after the
type/scope (or a `BREAKING CHANGE:` footer) marks a breaking change.

**This applies going forward only — existing git history is not being
rewritten.** `release.sh`'s changelog generation groups whatever commit
messages it finds since the last tag; commits that predate this convention
(or any future commit that doesn't follow it) simply land in an "Other"
section rather than being dropped or causing an error.

## Semantic versioning via git tags

Versions are tracked as annotated-or-lightweight `vX.Y.Z` git tags (e.g.
`v0.1.0`, `v1.2.3`) — no version file to keep in sync by hand.

**No tag exists yet in this repo.** `release.sh` handles that itself: if it
finds no `vX.Y.Z` tag, it falls back to treating `v0.1.0` as the baseline
("pre-release / not yet versioned") and computes the new version from
there. It does **not** create that first tag for you.

When you're ready to cut the first real release, create the tag yourself
once `release.sh` has produced a build you're happy with:

```sh
git tag v0.1.0
```

(`release.sh` never creates or pushes tags on your behalf — see below.)

## `release.sh` — local release packaging

```sh
Scripts/release.sh <patch|minor|major>
# e.g.
Scripts/release.sh patch
```

### Version-bump strategy

**Explicit CLI argument** (`patch` / `minor` / `major`), not automatic
inference from commit types. This is a deliberate, simple choice: you
decide what kind of release this is, the script just does the arithmetic
against the latest `vX.Y.Z` tag (or the `v0.1.0` fallback baseline
documented above) and the packaging. An alternative — inferring the bump
from Conventional Commit types since the last tag (`feat:` → minor,
`fix:`/other → patch, `!`/`BREAKING CHANGE:` → major) — was considered and
intentionally not built, to keep this script's logic easy to verify by
reading it. `CHANGELOG.md` generation *does* still classify commits by
type and calls out anything marked breaking, independent of the bump
argument you pass.

### What it does

1. Reads the current version from the latest `vX.Y.Z` tag (or the `v0.1.0`
   fallback).
2. Bumps it per the CLI argument.
3. Regenerates `CHANGELOG.md`: a new `## vX.Y.Z - <date>` section is
   prepended, built from `git log` since the last tag, grouped by
   Conventional Commit type (Features / Bug Fixes / Refactoring / ... /
   Other), with a separate "Breaking Changes" group for any commit using
   `!` or a `BREAKING CHANGE:` footer. Hand-rolled shell (`git log` +
   `sed`/`grep` + a temp-dir-per-type accumulator) — no external
   dependency.
4. Builds `MCleanPro-DeveloperID` in **Release** configuration via
   `xcodebuild`.
5. Packages the built `.app` into a `.dmg` under `dist/` (gitignored) via
   `hdiutil` — always available on macOS, the guaranteed path. If
   `create-dmg` happens to be installed it's tried first for a nicer
   drag-to-install layout, and falls back to `hdiutil` on any failure, so
   packaging never fails just because a third-party tool isn't present.
6. **Signing check, printed loudly either way.** It runs
   `codesign -dv --verbose=4` on the built `.app` and looks for an
   `Authority=Developer ID Application: ...` line. The user has confirmed
   there is no paid Developer ID Application certificate yet (and none is
   needed for personal use on this Mac) — so today, every build is
   expected to come back either unsigned or signed with Xcode's automatic
   personal-team/ad-hoc identity, **not** a real Developer ID. If the
   check does *not* find a Developer ID Application authority, the output
   filename gets an explicit `-unsigned-local-build-only` suffix (e.g.
   `MCleanPro-DeveloperID-v0.1.0-unsigned-local-build-only.dmg`) and the
   console output says so as well. Only a build actually signed with a
   real Developer ID Application certificate gets the plain
   `MCleanPro-DeveloperID-vX.Y.Z.dmg` name. If packaging itself fails for
   any reason, the script prints a clear error and exits non-zero — it
   never fails silently and never produces a `.dmg` that looks
   distribution-ready when it isn't.

### What it never does

- Never runs `git push`, never uploads or publishes anything anywhere, and
  makes no network calls at all. Its job ends at producing a local `.dmg`.
- Never creates a git commit or tag on your own behalf. It writes
  `CHANGELOG.md` to your working tree and prints the exact follow-up
  commands (`git add`, `git commit`, `git tag vX.Y.Z`) for you to run once
  you've reviewed the result — tagging a release is a deliberate human
  action, not something a script should do unattended.
- Nothing here runs on its own; it only runs when you invoke it.
