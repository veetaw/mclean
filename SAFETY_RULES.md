# Safety rules

Everything on this page is implemented and tested (`Packages/SafetyRules`,
42 tests) and wired into the app: `MainAppUI`'s `QuarantineConfirmationSheet`
is the only UI path to `FileSystemQuarantineManager`, and `SafetyClassifier`
is the single chokepoint every detector's findings pass through before
anything is ever offered for deletion. Checkpoint 4 (the rule-file format)
is **closed** — see "Rule files" below and `ARCHITECTURE.md`'s decisions
log. `Shredder` (see its own section below) is the one deliberate,
consciously-scoped exception to the quarantine flow this whole document
otherwise describes.

## Three-tier classification

Every discovered item (`CoreScanEngine.ScanItem`) is classified into exactly
one of three verdicts (`SafetyRules.SafetyVerdict`) before it can ever be
offered for deletion:

1. **`forbidden`** — matches the hardcoded `Denylist`. Never offered for
   deletion anywhere in the UI, under any settings or "advanced mode". This
   list is compiled into the app, not loaded from a file, and cannot be
   edited or bypassed by the user. See `Packages/SafetyRules/Sources/SafetyRules/Denylist.swift`
   for the current list.

2. **`safeAuto`** — matches a versioned, user-inspectable rule explicitly
   marked `safe-auto` in the rule file (e.g. system temp files expired for
   N+ days). May be deleted without a per-item confirmation dialog, but
   still goes through quarantine — never an instant, irreversible delete.

3. **`needsConfirmation`** — everything else. Always requires explicit
   per-item (or reviewed per-batch) user confirmation before moving to
   quarantine.

## Hardcoded denylist (non-negotiable, not user-editable)

Currently compiled into `Denylist.swift`:

- `/System`
- `/usr` (except `/usr/local`, the Homebrew-managed subtree)
- `/private/var/db`
- `/Library/Keychains`
- `/dev`
- Boot/external volume roots themselves (`/`, `/Volumes/<Name>`) — files
  *within* an external/network volume are not forbidden outright, only
  ineligible for `safe-auto` (see "Non-boot volumes" below)
- Filenames matching protected patterns: active kernel extensions (`.kext`),
  license files (`.license`), `.env` files, `*.pem`/`*.key` (private
  keys/certificates) — even when found inside an otherwise-safe cache or
  build directory
- Credential directories, home-relative: `~/.ssh`, `~/.gnupg`, `~/.aws`,
  `~/.config/gcloud`, `~/.kube`, `~/.azure`
- Any path inside a git repository with uncommitted changes (`git status
  --porcelain` non-empty) — implemented once, at the shared classification
  chokepoint (`Denylist.forbiddenReason`), so it applies to every
  detector's findings automatically, not just Node's `node_modules`.
  Fails open (doesn't block) if `git` isn't installed or no `.git`
  ancestor is found — the item still defaults to `needsConfirmation`.

This list is deliberately small and defensive; extending it is safe and
welcome, but nothing here should ever be *removed* without strong
justification reviewed by the user.

### Non-boot volumes

Never proposed for `safe-auto` — a matching official/user rule is
downgraded to `needsConfirmation` for anything under `/Volumes/`
(`Denylist.isOnNonBootVolume`), so external/network drives are never
auto-cleaned unattended, but a user can still explicitly confirm cleanup
there.

## Quarantine

- Default retention: **7 days**, user-configurable (`QuarantinePolicy`).
- Nothing is permanently deleted except via `purgeExpired()`, which must
  never run implicitly — only from an explicit user action or a scheduled
  job the user has knowingly enabled.
- Every quarantine action produces a `QuarantineReceipt` so it can be
  restored, and the UI can always show "what's sitting in quarantine and
  when it disappears."

## Dry-run

Every `Detector.scan(context:)` call is read-only by construction —
`CoreScanEngine` has no code path that deletes or moves files. `ScanContext.dryRun`
exists so call sites stay explicit about intent even before any deletion
capability exists.

## Rule files (checkpoint 4 — closed)

Two YAML files, loaded and merged by `RuleFileLoader`:

- **Official rules** — `Packages/SafetyRules/Sources/SafetyRules/Resources/official_rules.yaml`,
  shipped read-only as an SPM resource inside the app bundle. Overwritten
  by every app update; never touched by the running app itself.
- **User rules** — `~/Library/Application Support/MCleanPro/user_rules.yaml`,
  created empty (with example comments) on first load if absent. Never
  touched by an app update.

```yaml
version: 1
rules:
  - id: official.system.expired-temp-files
    description: "System temp files not modified in 30+ days"
    classification: safe-auto     # or: needs-confirmation — never forbidden
    match:
      pathGlob: "/private/var/folders/**"
      minimumAgeDays: 30
    introducedInVersion: 1
```

- `classification` can only be `safe-auto` or `needs-confirmation` — the
  file format cannot express `forbidden`. The hardcoded denylist above is
  the only source of forbidden rules, by design, so neither rule file
  (even a maliciously edited one) can ever grant back access to a
  protected path.
- `pathGlob` supports `*` (matches within one path component) and `**`
  (matches across component boundaries, any depth) — see `GlobMatcher`.
- **Merge is conservative, not last-write-wins**: for a given item, if any
  matching rule (from either file) says `needs-confirmation`, that wins
  over any matching `safe-auto` rule, regardless of source. A user rule
  can therefore add a brand-new `safe-auto` match nothing official covers,
  or narrow an official `safe-auto` rule with a stricter
  `needs-confirmation` match — but can never flip an official
  `needs-confirmation` decision into `safe-auto`.
- `official_rules.yaml` ends with a visible `TODO: add machine-specific
  paths here` block — deliberately left for you to fill in yourself rather
  than guessed at.

### Integrity check

At load time, `RuleFileLoader` computes `official_rules.yaml`'s SHA-256
and compares it against `OfficialRulesIntegrity.expectedSHA256Hex` (a
constant embedded in the binary, regenerated via
`Scripts/update-official-rules-hash.sh` whenever the file changes — run
this and commit both together after any edit). On a mismatch: the app is
**not** blocked, but every official `safe-auto` rule is downgraded to
`needs-confirmation` (not discarded — `needs-confirmation` rules stay
trusted), and a visible warning appears in Settings
(`AppEnvironment.safetyRulesIntegrityWarning`). This is a corruption/
tamper *detector*, not a cryptographic signature — sufficient to catch
"file was modified by something other than an app update," not a defense
against an attacker who can also patch the binary. User rules are not
subject to this check; they're inherently user-authored and trusted the
same way any of your other local settings are.

## Shredder — the deliberate exception to everything above

`Shredder` (secure multi-pass single-file deletion) never quarantines —
see `ARCHITECTURE.md`'s "Shredder: the quarantine exception" section for
the full rationale, its two-step API, and the honest SSD/APFS limitations
that mean "shredded" means *significantly harder to recover*, not
*cryptographically guaranteed gone*. It is still denylist-gated at both of
its steps, independently, exactly like every path above — the exception is
scoped strictly to bypassing quarantine, not to bypassing the denylist.
