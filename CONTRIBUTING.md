# Contributing to MClean Pro

Thanks for considering a contribution. This is an MIT-licensed open source
project; external contributions are welcome, with extra care expected on
anything that touches file deletion, permissions, or remote control — see
"Safety-critical changes" below before opening a PR in those areas.

## Getting set up

- Xcode with a Swift 6 toolchain, macOS 26 (Tahoe) or later.
- [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
  to generate `App/MCleanPro.xcodeproj` — it's gitignored and regenerated
  from `App/project.yml`, never hand-edited or committed.
- No other external tooling required; each package under `Packages/` is a
  normal Swift Package Manager package.

```sh
git clone <this repo>
cd MClean-pro
for pkg in Packages/*/; do (cd "$pkg" && swift build && swift test); done
cd App && xcodegen generate
xcodebuild -project MCleanPro.xcodeproj -scheme MCleanPro-DeveloperID -configuration Debug build
```

See `README.md` for the full build instructions and `ARCHITECTURE.md` for
the module graph.

## Project structure

This is a monorepo of small, single-purpose SPM packages under `Packages/`
rather than one large app target. If you're adding a feature, it almost
certainly belongs in an existing package or as a new one — see
`ARCHITECTURE.md`'s module graph before creating a new top-level package,
and keep new packages' dependencies as narrow as the existing ones (most
depend only on `CoreScanEngine`, sometimes `SafetyRules`).

## Code style

- English for all code, comments, commit messages, and docs — this file
  included — regardless of what language an issue or discussion started in.
- Match the idiom already in the file/package you're touching rather than
  introducing a new pattern for the same problem.
- Every detector/inspector that reads the filesystem or shells out to a
  CLI must degrade gracefully (return no results) rather than throw when
  the underlying tool/path isn't present — see any existing `*Detector.swift`
  for the pattern.
- Swift 6 strict concurrency is on repo-wide. Prefer actors/`@MainActor`
  isolation over `@unchecked Sendable`; if you do need `@unchecked Sendable`,
  justify it in a comment at the declaration (see
  `Packages/MenuBarAgent/Tests/.../TestSupport.swift` for the only
  precedent in the repo, and note it's test-only).

## Testing expectations

- New logic needs real unit tests, not just a manual "I ran it once" check
  — see any existing package's `Tests/` directory for the house style
  (temp-directory fixtures, injectable clocks/command-runners rather than
  depending on real installed tools or real wall-clock time).
- Run the full suite (`for pkg in Packages/*/; do (cd "$pkg" && swift test); done`)
  before opening a PR.
- If your change touches `SafetyRules`, `RemoteControlServer`'s approval
  flow, or anything else on the path to a real file being moved/deleted,
  see "Safety-critical changes" below — the bar for tests is higher there.

## Safety-critical changes

This app's entire value proposition depends on never surprising a user
with a deletion they didn't ask for. Changes in these areas get extra
scrutiny:

- **`Packages/SafetyRules`** — the hardcoded `Denylist`, `SafetyClassifier`,
  and `FileSystemQuarantineManager`. A PR that weakens the denylist, adds a
  code path that deletes (not moves-to-quarantine) a file, or makes
  `purgeExpired()` runnable implicitly will be rejected outright — see
  `SAFETY_RULES.md` for the non-negotiable constraints this project is
  built on.
- **Any new detector** (`Packages/DevToolsDetectors`, `MobileDevDetectors`,
  `PowerUserInspectors`) — must be strictly read-only (produces `ScanItem`s
  only, never touches disk destructively) and must not shell out to a
  mutating subcommand (no `rm`, `prune`, `uninstall`, etc.) — see
  `TESTING.md`'s repo-wide audit commands, which should still come back
  clean after your change.
- **`Packages/RemoteControlServer`** — anything on the path from an HTTP
  request to `QuarantineManaging.quarantine(...)` (currently exactly one
  call site, in `resolveApprovalRequest`) needs the same forbidden-verdict
  and confirmation guarantees as the desktop UI, not a shortcut because
  "it's just the mobile client."

If you're not sure whether a change falls into this category, open an
issue/draft PR and ask before investing a lot of time in an approach that
might not be accepted.

## Reporting a security issue

If you find something that lets a file be deleted without confirmation,
bypasses the denylist, or otherwise breaks this project's safety
guarantees, please don't open a public issue — see the repository's
security policy (or, if none is published yet, contact the maintainer
directly) so it can be fixed before the report is public.

## Pull requests

- Keep PRs scoped to one package/concern where possible — this repo's own
  git history (one commit per module) is the model to follow.
- Explain *why*, not just *what*, in the PR description, especially for
  any behavior change in a detector's heuristics (staleness thresholds,
  what counts as "last used") or in `SafetyRules`.
- Update `ARCHITECTURE.md`'s status table and, if relevant, `SAFETY_RULES.md`
  or `TESTING.md`, in the same PR as the code change — not as a follow-up.
