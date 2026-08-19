# Testing

## Automated coverage

Every package under `Packages/` has its own `swift test` suite. As of this
writing, **345 tests pass across 15 packages**, verified independently
(not just trusted from whatever built them) with a clean `.build` for each:

| Package | Tests |
|---|---|
| CoreScanEngine | 1 |
| SafetyRules | 42 |
| PrivilegedHelperXPC | 1 |
| VirusTotalClient | 1 |
| DevToolsDetectors | 44 |
| MobileDevDetectors | 30 |
| PowerUserInspectors | 70 |
| MenuBarAgent | 37 |
| UIDesignSystem | 7 |
| RemoteControlServer | 27 |
| MainAppUI | 14 |
| TrashCleaner | 20 |
| LargeOldFilesFinder | 16 |
| DuplicateFinder | 19 |
| Shredder | 16 |

Run all of them:

```sh
for pkg in Packages/*/; do (cd "$pkg" && swift test); done
```

### Safety-critical coverage (SafetyRules)

Per the product spec, this is the module that most needs high confidence:

- `DenylistTests` — every hardcoded protected path/pattern is matched, and
  ordinary user paths are confirmed *not* matched (a false positive here
  would make the app refuse to clean anything; a false negative would be
  far worse).
- `SafetyClassifierTests` / `SafetyClassifierRuleMatchingTests` — forbidden
  paths classify as `.forbidden`; everything else defaults to
  `.needsConfirmation` unless an official/user rule matches; the
  conservative merge (needs-confirmation always beats safe-auto for the
  same item, regardless of source) is directly tested, including the case
  of a user rule attempting to loosen an official needs-confirmation
  decision.
- `DenylistCheckpoint4Tests` — credential directories, `.env`/`.pem`/`.key`
  patterns, the dirty-git-repo check (against a real git repository
  fixture, not simulated), and the non-boot-volume safe-auto downgrade.
- `RuleFileLoaderTests` — the real bundled `official_rules.yaml` loads with
  a matching hash; a hash mismatch downgrades every official safe-auto
  rule and sets a warning; a missing/malformed rule file degrades to "no
  rules from that source" rather than crashing; `user_rules.yaml` is
  created with example comments on first load.
- `FileSystemQuarantineManagerTests` — quarantine/restore round-trip,
  refusal to quarantine a forbidden path, refusal to restore over an
  occupied destination, retention-based purge (only expired items are
  purged), and manifest persistence across separate manager instances
  (i.e. across app restarts).

### Safety-critical coverage (Shredder)

The one deliberate exception to the quarantine flow — see
`ARCHITECTURE.md`'s "Shredder: the quarantine exception" section. Its own
`ShredderTests` cover: the two-step API can't be bypassed (`ShredRequest`
has no accessible public initializer); denylist rejection at both
`requestShred` and `confirmShred` time, including a path that became
forbidden *after* the request was created and a symlink swapped in after
the request (closing the TOCTOU window with `O_NOFOLLOW`); pass content is
directly verified (pass 2 is genuinely all-`0xFF`, not just "assumed to
have happened"); cancellation never leaves a partially truncated or
partially deleted file.

### Repo-wide destructive-action audit

Ran manually as part of Phase 3, re-run any time before a release:

```sh
# Every FileManager.removeItem call outside Tests/ should be one of:
#  - SafetyRules/FileSystemQuarantineManager.swift: purgeExpired() (the one
#    documented irreversible operation, retention-gated, never auto-run)
#    and restore()'s best-effort empty-folder cleanup (the file itself was
#    already moved out by the time this runs)
#  - PowerUserInspectors/ConfigFileExplorer.swift: removing a *stale
#    same-named backup file* immediately before writing a fresh one, not
#    user data
#  - Shredder/Shredder.swift: confirmShred's final removeItem, only after
#    every overwrite pass has completed and been fsync'd — this is
#    Shredder's own documented, deliberate exception to quarantine, not a
#    new unaudited path (see ARCHITECTURE.md's "Shredder" section)
grep -rn "\.removeItem(" Packages --include="*.swift" | grep -v "/Tests/"

# No detector/inspector should ever invoke a mutating subcommand.
grep -rn '"prune"\|"rmi"\|"uninstall"' Packages --include="*.swift" | grep -v "/Tests/"

# Shredder.swift should be the only file in the whole repo opening a file
# for writing with a raw POSIX open() call. --exclude-dir=.build matters
# here: XCTest's own generated test-discovery runner.swift files use
# O_WRONLY internally for lock-file coordination and will otherwise show
# up as false positives (they're gitignored build output, not source).
grep -rln --exclude-dir=.build "open(.*O_WRONLY" Packages --include="*.swift" | grep -v "/Tests/"
```

All three should come back matching only the call sites named above.

## Manual test checklist

The following can't reasonably be automated in CI — they need a live Mac,
a live phone, and/or real system permission dialogs. Run through this list
before any release and after any change touching pairing, onboarding, or
permission flows.

### Remote pairing flow

- [ ] Start pairing from the Mac app (`RemoteControlServer.beginPairing()`
      via the Remote Control tab); confirm a QR/token is displayed.
- [ ] From a phone on the **same LAN**, open the pairing URL (or type the
      token into `RemoteWebApp`'s pairing screen manually) — confirm
      pairing succeeds and the status/findings screens load.
- [ ] From a phone on a **different network** (e.g. cellular, not the same
      Wi-Fi), confirm the server is unreachable — no code path should
      accept it (see `LANGuard`).
- [ ] Let a pairing invitation expire (default 5 minutes) without
      redeeming it; confirm the token is then rejected.
- [ ] Redeem a pairing token twice; confirm the second attempt is rejected
      (single-use).
- [ ] From the paired phone, request approval on a `needsConfirmation`
      finding; confirm it shows as pending on the Mac and nothing is
      quarantined until fulfilled.
- [ ] Confirm a `forbidden`-verdict item can never reach the "request
      approval" flow, on both the Mac UI and the mobile web app.
- [ ] Revoke the device's own token from the mobile web app (self-unpair);
      confirm subsequent requests 401 and the mobile app returns to the
      pairing screen.
- [ ] Revoke a paired device from the Mac app; confirm that device's next
      request 401s.
- [ ] Toggle `allowMobileApprovalFulfillment` off (the default) and confirm
      the mobile app can request approval but not resolve it; toggle it on
      and confirm resolution from mobile now works.

### Permission onboarding

- [ ] Fresh install / reset TCC state (`tccutil reset All com.mcleanpro.app`
      on a test machine only), launch the app, and confirm onboarding
      explains *why* each permission (Full Disk Access, Accessibility,
      Local Network) is being requested **before** the system prompt
      appears — never a bare system dialog with no context.
- [ ] Decline every permission during onboarding; confirm the app still
      launches and is usable, with clear messaging about which features
      are unavailable (never a crash or a dead-end screen).
- [ ] Grant Full Disk Access after initially declining (via the
      System Settings deep link the app provides); confirm the
      previously-degraded features recover without requiring a reinstall.
- [ ] Confirm there is no code path that requests a permission silently,
      outside the onboarding flow's explanatory screens.

### App Store vs. Developer ID build behavior

- [ ] Build and run `MCleanPro-AppStore`; confirm the sandbox-limitation
      banner is visible, the Remote Control **and Shredder** sections are
      entirely absent (not just disabled) from the sidebar, and no
      privileged-helper / broad-filesystem-scan code path is reachable.
- [ ] Build and run `MCleanPro-DeveloperID`; confirm the banner is absent
      and both Remote Control and Shredder are available.

### Shredder (destructive, irreversible — test with throwaway files only)

- [ ] From the Shredder tab, pick a real (disposable, non-important) test
      file; confirm the first confirmation sheet shows its correct path
      and size before anything happens on disk.
- [ ] Confirm the first sheet, then confirm the second (graver) sheet;
      watch the pass-progress indicator; confirm the file is gone from
      Finder afterward and does **not** appear anywhere in the Quarantine
      tab (it deliberately bypasses quarantine).
- [ ] Cancel at the first sheet; confirm the file is completely untouched
      (unchanged size/mtime/content).
- [ ] Attempt to shred a file matching a hardcoded denylist pattern (e.g. a
      throwaway `.pem` file, or something under `~/.ssh`); confirm
      `requestShred` refuses it before the first confirmation sheet even
      appears.
- [ ] Attempt to shred a file inside a git repository with uncommitted
      changes; confirm it's refused with a message naming the dirty repo.
- [ ] Confirm the on-screen honesty text about SSD/APFS limits is visible
      and is never phrased as a guarantee ("makes recovery significantly
      harder," not "guarantees unrecoverable").

### System Junk (Trash / Large & Old Files / Duplicates)

- [ ] Put a real (disposable) item in the Finder Trash; rescan; confirm it
      appears in the System Junk findings list with the correct size.
- [ ] Create two byte-identical throwaway files somewhere scanned by
      default (e.g. `~/Downloads`); rescan; confirm both are grouped as an
      exact duplicate, with the kept "original" correctly identified.
- [ ] Create two near-identical images (e.g. the same photo saved twice at
      different JPEG quality) and two clearly different images; rescan;
      confirm only the near-identical pair is grouped as similar.
- [ ] Confirm nothing from Developer Tools/Mobile Dev/Power User's own
      territory (e.g. `node_modules`, `~/.gradle`) shows up duplicated in
      System Junk's results.

### Quarantine lifecycle (can be scripted, but worth a manual pass too)

- [ ] Quarantine a real (test) file from the UI; confirm it disappears
      from its original location and appears in the Quarantine tab with a
      correct purge-eligible date.
- [ ] Restore it; confirm it reappears at the original path with unchanged
      contents.
- [ ] Manually trigger "purge expired" on an item whose retention window
      has elapsed; confirm only that item is removed and it's genuinely
      gone (not recoverable) — and confirm this action requires an
      explicit user click, never happens automatically in the background.
