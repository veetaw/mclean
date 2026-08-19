# Safety rules

> ⚠️ **The rule-file format section below is a draft pending your review**
> (checkpoint 4 — still open). Everything *else* on this page — the
> three-tier classification, the hardcoded denylist, and the quarantine
> mechanism — is implemented and tested (`Packages/SafetyRules`, 14 tests)
> and already wired into the app (`MainAppUI`'s `QuarantineConfirmationSheet`
> is the only UI path to `FileSystemQuarantineManager`). Only the
> user-editable `safe-auto` rule file itself remains unimplemented: until
> its format is confirmed, `SafetyClassifier` defaults every non-forbidden
> item to `needsConfirmation` — the safe fallback.

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
- Boot/external volume roots themselves (`/`, `/Volumes/<Name>`)
- Filenames matching protected patterns: active kernel extensions (`.kext`),
  license files (`.license`)
- A repository with uncommitted changes (`git status` is not clean) must
  never be proposed for cleanup — this check is planned for
  `DevToolsDetectors`, not yet implemented.

This list is deliberately small and defensive; extending it is safe and
welcome, but nothing here should ever be *removed* without strong
justification reviewed by the user.

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

## Proposed rule file format (draft — see `RuleSetDraft.swift`)

Proposed as a versioned YAML document, one rule per entry:

```yaml
version: 1
rules:
  - id: dev.system.expired-temp-files
    description: "System temp files not modified in 30+ days"
    classification: safe-auto     # or: needs-confirmation
    match:
      pathGlob: "/private/var/folders/**"
      minimumAgeDays: 30
    introducedInVersion: 1
```

Notes on the shape, for review:

- `classification` can only be `safe-auto` or `needs-confirmation` — the
  file format cannot express `forbidden`. The hardcoded denylist is the only
  source of forbidden rules, by design, so a rule file (even a maliciously
  edited one) can never grant back access to a protected path.
- `match` is intentionally a narrow glob + age filter, not a general
  expression language, so the file stays auditable by a non-programmer.
- Rules are additive to the built-in defaults; the app should ship a
  default rule set and let the user layer their own on top, not replace it
  wholesale.

**Open questions for the user before finalizing:**
- Should user-authored rules live in `~/Library/Application Support/MCleanPro/rules.yaml`,
  or somewhere more visible/editable?
- Should there be a signed/verified "official" rule set separate from user
  overrides, so a compromised rules file can't silently mark dangerous
  paths `safe-auto`?
- Any additional hardcoded denylist entries you want included from day one?
