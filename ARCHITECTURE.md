# Architecture

## Module graph

```
CoreScanEngine  (no deps)
  ├─ SafetyRules            (depends on CoreScanEngine, Yams)
  │    └─ Shredder          (depends on SafetyRules only — see "Shredder" below)
  ├─ DevToolsDetectors      (depends on CoreScanEngine)
  ├─ MobileDevDetectors     (depends on CoreScanEngine)
  ├─ TrashCleaner           (depends on CoreScanEngine)
  ├─ LargeOldFilesFinder    (depends on CoreScanEngine)
  ├─ DuplicateFinder        (depends on CoreScanEngine)
  └─ RemoteControlServer    (depends on CoreScanEngine, SafetyRules, Swifter)

PrivilegedHelperXPC (no deps)
  └─ PowerUserInspectors    (depends on CoreScanEngine, PrivilegedHelperXPC)

SafetyRules
  └─ MenuBarAgent           (depends on CoreScanEngine, SafetyRules)

UIDesignSystem   (no deps)
VirusTotalClient (no deps)

MainAppUI (depends on UIDesignSystem + every module above, incl. Shredder)
  └─ App/AppStoreTarget, App/DeveloperIDTarget (thin @main entry points, xcodegen)
```

`PrivilegedHelper` (the actual executable target registered via
`SMAppService`) is not scaffolded yet — it will depend only on
`PrivilegedHelperXPC` for the protocol definition, kept intentionally
narrow since it runs with elevated privileges.

## Status by module

| Module | Status |
|---|---|
| CoreScanEngine | `Detector` protocol, `ScanItem`, concurrent `ScanEngine` actor. Read-only by construction. **1 test.** |
| SafetyRules | `SafetyVerdict`, hardcoded `Denylist` (incl. checkpoint 4's credential-directory/sensitive-file-pattern/dirty-git-repo/non-boot-volume additions), `SafetyClassifier` with the closed-checkpoint-4 official+user rule-file system (Yams-parsed, SHA-256 integrity check, conservative merge), and the **real** `FileSystemQuarantineManager` (reversible move-based quarantine, JSON manifest, independent denylist re-check). **42 tests.** |
| PrivilegedHelperXPC | XPC protocol defined. No helper executable or entitlements yet. **1 test.** |
| VirusTotalClient | Hash-check-first protocol + rate limiter. No concrete network implementation yet. **1 test.** |
| DevToolsDetectors | 10 toolchain detectors (Python/Node/Rust/Go/Ruby/Java/Docker/Xcode/Homebrew/editors), all read-only. **44 tests.** |
| MobileDevDetectors | Android (AVD/SDK/Studio/Gradle-wrapper) + iOS (Simulator/CocoaPods/Fastlane) detectors. **30 tests.** |
| PowerUserInspectors | Installed apps, TCC listing (read-only, no revocation path), config file explorer (backup-before-write, always), per-language package explorer, JSON system report (PDF export deferred). **70 tests.** |
| MenuBarAgent | `NSStatusItem` controller, FSEvents-based background monitoring, low-disk-space notifications, scheduled health check, system stats. **37 tests.** |
| UIDesignSystem | Liquid Glass tokens/components (cards, buttons, safety badges, scan-result rows). **7 tests.** |
| RemoteControlServer | Swifter-based LAN HTTP server, Bonjour advertisement, two-phase pairing, approval workflow (single quarantine call site, defense-in-depth verdict re-check). **27 tests.** |
| RemoteWebApp | Vanilla HTML/CSS/JS mobile client matching the server's API contract (documented in `RemoteWebApp/README.md`). No camera QR scanning yet. |
| TrashCleaner | Finder Trash (boot + external volumes), best-effort Mail/Photos trash detectors (documented, undocumented-layout caveats). Browser trash deliberately not implemented — no genuine filesystem-visible equivalent exists. **20 tests.** |
| LargeOldFilesFinder | Configurable size/age/type-filtered scan, scoped to common user content folders (not a blind home-directory walk). **16 tests.** |
| DuplicateFinder | Exact-match (SHA-256, size-bucketed) + perceptual-hash (dHash + luminance) similar-image detection. **19 tests.** |
| Shredder | Secure multi-pass single-file deletion — the **one deliberate exception** to the quarantine flow. See "Shredder: the quarantine exception" below. **16 tests.** |
| MainAppUI | `Capabilities`/`BuildFlavor` registry, `AppEnvironment` composition root, full `NavigationSplitView` app (Dashboard, System Junk, Developer Tools, Mobile Dev, Power User, Quarantine, Shredder, Remote Control, Settings, onboarding). **14 tests.** |
| App/ | `project.yml` (xcodegen) generating `MCleanPro-AppStore` (sandboxed) and `MCleanPro-DeveloperID` (unsandboxed, hardened runtime) — both verified to build with `xcodebuild`, including all 15 packages. |
| PrivilegedHelper/, Scripts/ | Directory scaffolding only, plus `Scripts/update-official-rules-hash.sh` — no privileged-helper executable yet. |

**Total: 345 tests passing across 15 packages**, verified independently at every step (not trusted from any implementing agent's self-report) with clean `.build` directories and, for `MainAppUI`, both Xcode targets actually building via `xcodebuild`.

**Remaining gap:** the product spec's §5.1 "System Junk" scope is now
**partially** closed — Trash Bins, Large & Old Files, Duplicates, and
Shredder exist (Phase 5). Still unbuilt: system/user cache cleanup
proper, an app **Uninstaller**, **Optimization** (login items/launch
agents review), a **Privacy cleaner** (browser cookie/history/cache, with
a preserve-list), **maintenance scripts** (flush DNS, rebuild Spotlight
index, etc.), and **Space Lens** (interactive disk-usage treemap). No
package implements any of these yet.

## Shredder: the quarantine exception

Every other destructive-adjacent path in this app — every detector's
findings, `RemoteControlServer`'s approval flow — funnels through
`SafetyRules.FileSystemQuarantineManager`: nothing is instantly and
irreversibly gone, everything is reversible for a retention window.
`Shredder` (Phase 5) is the **one deliberate, conscious exception**,
because a secure multi-pass overwrite is only meaningful if it's actually
irreversible immediately — quarantining the file first (still fully
intact, just moved) would defeat the entire point.

Because of that, `Shredder` carries safety obligations the quarantine flow
gets structurally for free elsewhere in this app:

- **Never reachable from the scan pipeline.** `Shredder` is not a
  `CoreScanEngine.Detector`, has no dependency on `CoreScanEngine`, and is
  never registered with `ScanEngine`. A scan verdict can never feed a path
  into it automatically — only `MainAppUI`'s `ShredderView`, via an
  explicit user file selection, ever calls it.
- **Two-step API by construction, not convention.** `requestShred(path:)`
  validates and returns a `ShredRequest` (never touches file content);
  `confirmShred(_:passes:)` is the only method that ever opens/writes/
  deletes, and only accepts a `ShredRequest` — there is no path from a raw
  string straight to destruction. `ShredderView` puts two separate,
  increasingly grave confirmation dialogs between the two steps.
- **Still denylist-gated, independently, at both steps** — the same
  `SafetyRules.Denylist.forbiddenReason`/`isLikelyBootVolumeRoot` checks
  every other destructive path uses, re-run at `confirmShred` time too in
  case a held `ShredRequest` went stale.
- **Developer-ID-only.** `Capabilities.canRunShredder` is `false` in the
  App Store flavor: `Shredder` does raw POSIX `open`/`write`/`ftruncate`
  on a resolved path rather than through a persisted security-scoped
  bookmark, and that hasn't been verified to behave correctly under the
  App Sandbox. `ContentView` hides the sidebar section entirely (not just
  disables it) when the capability is off.

**Honest limits — multi-pass overwrite is not a cryptographic guarantee.**
On the SSD/APFS setup every supported Mac uses, wear leveling and TRIM
mean an SSD's flash translation layer routinely does *not* reuse the same
physical NAND cells a previous write to the same logical offset used —
overwriting a file's logical bytes repeatedly is not the same as
overwriting the physical cells that held the *original* data. APFS
copy-on-write means a cloned or Time-Machine-snapshotted file's overwrite
lands on freshly allocated blocks, leaving the blocks the clone/snapshot
references untouched. Hard links to the same inode aren't detected or
blocked — other names survive pointing at destroyed data after the given
name is unlinked. `Shredder`'s own doc comment (`Packages/Shredder/Sources/Shredder/Shredder.swift`)
carries the full technical explanation. **UI copy for this feature must
say "makes recovery significantly harder," never "guarantees the data is
unrecoverable"** — full-disk encryption (FileVault, already standard) and
destroying key material is the more reliable primitive on SSDs in general.

## Checkpoints (PROMPT MASTER §10) — decisions log

1. **Local HTTP server library for `RemoteControlServer`** — **decided:
   Swifter.** Small, embeddable, no heavy async-networking stack to carry
   for what is a single-client-at-a-time, LAN-only server. Trade-off
   accepted: Swifter is lightly maintained upstream, so `RemoteControlServer`
   should keep its own usage surface narrow (routing + request/response
   only) so swapping it out later stays cheap if needed. Not yet wired into
   `Package.swift` — happens when the Phase 2 `RemoteControlServer` agent
   implements the module.
2. **Real deletion/quarantine code path** — **decided: implement now.**
   Quarantine is reversible by design (move, not delete; 7-day default
   retention; explicit separate purge step), so the user approved building
   the concrete `FileSystemQuarantineManager` in Phase 1 rather than leaving
   it stubbed.
3. **Any system permission not already listed in the product spec** — none
   have come up yet; still tracked as a standing checkpoint.
4. **Final format of the safety rule file** — **closed.** Official rules
   ship read-only as an SPM resource (`Resources/official_rules.yaml`,
   SHA-256 integrity-checked against `OfficialRulesIntegrity.expectedSHA256Hex`);
   user rules live at `~/Library/Application Support/MCleanPro/user_rules.yaml`,
   created empty with example comments on first load, never touched by an
   app update. Merge is conservative: `needsConfirmation` always wins over
   `safeAuto` for the same item regardless of which file either rule came
   from, so a user rule can add or restrict but never loosen an official
   decision. See `SAFETY_RULES.md` for the full format and the denylist
   additions (credential directories, `.env`/`.pem`/`.key` patterns, dirty-
   git-repo check, non-boot-volume safe-auto downgrade) that came with this
   closure.

## Trade-offs

- HTTP vs. local TLS for the remote-control server (currently: HTTP + token
  auth, LAN-only, documented as an accepted trade-off pending a future
  mkcert-style local TLS option — see PROMPT MASTER §5.6).
- SPM packages declare `platforms: [.macOS(.v15)]` as a conservative build
  floor; the actual app targets will pin macOS 26 (Tahoe)+ as the real
  minimum deployment target, per the product spec.
- **Xcode project generation: xcodegen.** `swift package generate-xcodeproj`
  no longer exists in current SwiftPM, and hand-writing a `.pbxproj` blind
  is error-prone. Installed via Homebrew (`brew install xcodegen`); the
  `App/` target definitions are driven by a `project.yml` checked into the
  repo, with the generated `.xcodeproj` itself left out of git (regenerate
  with `xcodegen generate`) since generated Xcode project files churn noisily
  in diffs and are fully reproducible from `project.yml`.
- **YAML parsing: Yams.** Needed once checkpoint 4 closed the rule-file
  format as YAML. Same reasoning as Swifter for checkpoint 1: an approved
  feature needs a parser, Yams is the established Swift choice, kept to a
  narrow usage surface (`SafetyRules.RuleFileLoader` only).
- **Perceptual image hashing: difference hash (dHash) + average luminance,
  hand-rolled, no dependency.** A pure dHash is invariant to absolute
  brightness (a solid-black and solid-white image hash identically) —
  caught by `DuplicateFinder`'s own black-vs-white regression test during
  implementation, fixed by requiring both a small Hamming distance and
  close average luminance (`PerceptualHash.areSimilar`). This is a simple,
  well-understood, non-ML technique, not the Vision framework's feature-
  print APIs — deliberate, to keep the package dependency-free.
