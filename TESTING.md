# Testing

## Automated coverage

Every package under `Packages/` has its own `swift test` suite. As of this
writing, **246 tests pass across 11 packages**, verified independently
(not just trusted from whatever built them) with a clean `.build` for each:

| Package | Tests |
|---|---|
| CoreScanEngine | 1 |
| SafetyRules | 14 |
| PrivilegedHelperXPC | 1 |
| VirusTotalClient | 1 |
| DevToolsDetectors | 44 |
| MobileDevDetectors | 30 |
| PowerUserInspectors | 70 |
| MenuBarAgent | 37 |
| UIDesignSystem | 7 |
| RemoteControlServer | 27 |
| MainAppUI | 14 |

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
- `SafetyClassifierTests` — forbidden paths classify as `.forbidden`;
  everything else defaults to `.needsConfirmation` (the safe default, since
  `safe-auto` rule matching isn't wired in yet — see checkpoint 4).
- `FileSystemQuarantineManagerTests` — quarantine/restore round-trip,
  refusal to quarantine a forbidden path, refusal to restore over an
  occupied destination, retention-based purge (only expired items are
  purged), and manifest persistence across separate manager instances
  (i.e. across app restarts).

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
grep -rn "\.removeItem(" Packages --include="*.swift" | grep -v "/Tests/"

# No detector/inspector should ever invoke a mutating subcommand.
grep -rn '"prune"\|"rmi"\|"uninstall"' Packages --include="*.swift" | grep -v "/Tests/"
```

Both should come back empty except the three call sites listed above.

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
      banner is visible, the Remote Control section is entirely absent
      (not just disabled) from the sidebar, and no privileged-helper /
      broad-filesystem-scan code path is reachable.
- [ ] Build and run `MCleanPro-DeveloperID`; confirm the banner is absent
      and Remote Control is available.

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
