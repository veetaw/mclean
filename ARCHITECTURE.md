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
  ├─ CacheCleaner           (depends on CoreScanEngine)
  ├─ Optimization           (depends on CoreScanEngine)
  ├─ PrivacyCleaner         (depends on CoreScanEngine)
  └─ RemoteControlServer    (depends on CoreScanEngine, SafetyRules, Swifter)

PrivilegedHelperXPC (no deps)
  ├─ PowerUserInspectors    (depends on CoreScanEngine, PrivilegedHelperXPC)
  └─ Uninstaller            (depends on CoreScanEngine, PowerUserInspectors)

SafetyRules
  └─ MenuBarAgent           (depends on CoreScanEngine, SafetyRules)

UIDesignSystem   (no deps)
  └─ SpaceLens              (depends on UIDesignSystem only — no CoreScanEngine, pure visualization)

VirusTotalClient  (no deps)
MaintenanceScripts (no deps — fixed action set, not file discovery)

MainAppUI (depends on UIDesignSystem + every module above, incl. Shredder,
           Uninstaller, MaintenanceScripts, SpaceLens)
  └─ App/AppStoreTarget, App/DeveloperIDTarget (thin @main entry points, xcodegen)
```

`PrivilegedHelper` has no real executable target yet — see "PrivilegedHelper: mock/stub status" below.

## Status by module

| Module | Status |
|---|---|
| CoreScanEngine | `Detector` protocol, `ScanItem`, concurrent `ScanEngine` actor. Read-only by construction. **1 test.** |
| SafetyRules | `SafetyVerdict`, hardcoded `Denylist` (incl. checkpoint 4's credential-directory/sensitive-file-pattern/dirty-git-repo/non-boot-volume additions), `SafetyClassifier` with the closed-checkpoint-4 official+user rule-file system (Yams-parsed, SHA-256 integrity check, conservative merge), and the **real** `FileSystemQuarantineManager` (reversible move-based quarantine, JSON manifest, independent denylist re-check). **42 tests.** |
| PrivilegedHelperXPC | XPC protocol + `PrivilegedHelperClientProtocol` (Swift-native async seam) + `MockPrivilegedHelper` (in-memory simulation, no real elevation). No helper executable or `SMAppService` registration yet — see "PrivilegedHelper: mock/stub status" below. **11 tests.** |
| VirusTotalClient | **Real network implementation.** Hash-check (`GET /api/v3/files/{sha256}`, 404→nil), opt-in-only upload with genuine consent-gate-before-any-request, rate limiter with real suspend/backoff (not just accounting). **21 tests.** |
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
| CacheCleaner | User/app cache, user-writable logs, temp files, incomplete downloads, unused language packs (`.lproj`) — closes §5.1's "System Junk" cache-cleanup scope. **29 tests.** |
| Uninstaller | Per-app "find related files" service (Application Support/Preferences/Caches/Saved State/LaunchAgents/Containers, dot-boundary bundle-ID matching), full preview before anything moves. Not a `Detector` — invoked on demand from `UninstallerView` for one user-picked app. **7 tests.** |
| Optimization | Launch Agent detector (`~/Library/LaunchAgents` + `/Library/LaunchAgents` only, no root-owned locations), best-effort login-items/startup-impact reporting, honest about what a *complete* login-items list would require (Full Disk Access to a private store) and doesn't claim it. **20 tests.** |
| PrivacyCleaner | Safari/Chrome/Firefox cache/cookie/history detectors with a real, engine-honored site preserve list (`SitePreserveList` — excludes matching per-origin directories outright where browsers support that granularity; states plainly in `reason` where a monolithic store can't honor it at all). Settings UI to edit the list live is deferred — see below. **27 tests.** |
| MaintenanceScripts | Four fixed, reviewed actions (flush DNS, rebuild Spotlight index, verify startup disk, clear font cache) — each described before it can run, never automatic, never SafetyRules/quarantine (fixed command set, no arbitrary path). **28 tests.** |
| SpaceLens | Interactive disk-usage treemap — bounded/cancellable size-tree builder, pure squarified-layout algorithm (tiling/proportionality verified geometrically), SwiftUI drill-down view. Strictly read-only. **31 tests.** |
| MainAppUI | `Capabilities`/`BuildFlavor` registry, `AppEnvironment` composition root, full `NavigationSplitView` app — Dashboard, System Junk, Developer Tools, Mobile Dev, Power User, Optimization, Privacy, Uninstaller, Maintenance, Space Lens, Quarantine, Shredder, Remote Control, Settings, onboarding. **14 tests.** |
| App/ | `project.yml` (xcodegen) generating `MCleanPro-AppStore` (sandboxed, **paused from the active pipeline**, see below) and `MCleanPro-DeveloperID` (unsandboxed, hardened runtime — the only target `Scripts/ci.sh`/`release.sh` build). Both verified to build with `xcodebuild` as of the last time AppStore was exercised; DeveloperID is verified on every `ci.sh` run. |
| PrivilegedHelper/ | No real executable target — `PrivilegedHelperXPC.MockPrivilegedHelper` stands in. See "PrivilegedHelper: mock/stub status" below. |
| Scripts/ | `ci.sh`, `release.sh`, `pre-push-hook.sh`, `install-git-hooks.sh`, `update-official-rules-hash.sh` — see "Release pipeline" below. |

**Total: 487 tests passing across 21 packages**, verified independently at every step (not trusted from any implementing agent's self-report) with clean `.build` directories, and confirmed end-to-end via `Scripts/ci.sh` (`MCleanPro-DeveloperID` build + every package's tests, one command, real exit code).

**§5.1 scope: now fully covered at MVP level.** Every sub-feature from the
original product spec's §5.1 has at least a working implementation: System
Junk (cache/logs/temp/downloads/language packs), Trash Bins, Large & Old
Files, Duplicates, Uninstaller, Optimization, Privacy, Maintenance
Scripts, Space Lens, and Shredder. What's still deferred within that
scope, by design, is narrower than a missing feature:
- **PrivacyCleaner's site preserve-list has no Settings UI to edit it
  live** — the mechanism itself is real and engine-honored (see the table
  row above); a user just can't populate it without editing code today.
  Not a security gap: even with an empty/unconfigurable list, nothing is
  ever deleted without explicit per-item confirmation regardless.
- `PowerUserInspectors.SystemReportExporter.exportPDF()` always throws,
  documented as a UI-layer TODO (Phase 2) — JSON export works.
- `RemoteWebApp` has no camera-based QR scanning (Phase 2) — manual token
  entry / URL-prefill works.
- Several detectors' staleness thresholds are tunable constructor
  defaults, not yet exposed as user-facing Settings.

## Non-boot volume handling — a bug fix caught while closing checkpoint 4

**Before:** `Denylist.forbiddenPathPrefixes` included a bare `"/Volumes"`
entry. `forbiddenReason(forPath:)` matched any path with that prefix, so
**every file at any depth on any mounted external/network volume** was
classified `.forbidden` — the strictest tier, meaning "never proposable
for deletion anywhere in the UI, under any settings or advanced mode" (see
the three-tier classification above). In practice this excluded external
drives from cleanup entirely, including manual, explicitly-confirmed
actions — stricter than intended, and inconsistent with the inline
comment's own stated intent ("not arbitrary user files within a mounted
volume").

**After:** the bare `"/Volumes"` entry is removed. Volume *roots* (the
mount point itself, e.g. `/Volumes/MyExternalDrive` as a single item) are
still fully forbidden — via the separate, unchanged
`isLikelyBootVolumeRoot` check, so a whole external volume can never be
proposed for deletion as one unit. Ordinary files *within* a volume now
reach normal classification (denylist patterns/credentials/dirty-git-repo
checks still apply where relevant, then rule matching). Separately,
`Denylist.isOnNonBootVolume(path)` — checked only by `SafetyClassifier` —
downgrades a would-be `safeAuto` verdict to `needsConfirmation` for
anything outside the boot volume; it never affects an item that would
already be `needsConfirmation`, and never touches `forbidden` verdicts.

**Confirms the original intent** (checkpoint 4: "mai proporre pulizia
automatica fuori dal disco di boot"): auto-clean (`safeAuto`) is still
never possible for external/network volumes (`testNonBootVolumeDowngradesSafeAutoToNeedsConfirmation`,
`Packages/SafetyRules/Tests/SafetyRulesTests/SafetyClassifierRuleMatchingTests.swift`);
scanning/reporting is unaffected (detectors never consult the denylist —
only `SafetyClassifier` does, downstream of detection); manual,
per-item-confirmed cleanup is now correctly available, which the bug had
wrongly blocked
(`testExternalVolumeIsNotForbiddenButIsFlaggedNonBoot`,
`Packages/SafetyRules/Tests/SafetyRulesTests/DenylistCheckpoint4Tests.swift`).

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

## PrivilegedHelper: mock/stub status

**No real privileged helper exists.** `PrivilegedHelper/` has no
executable target — nothing in this codebase calls `SMAppService`,
installs a daemon, or opens an `NSXPCConnection` (confirmed by grep across
`Packages/PrivilegedHelperXPC/` and `PrivilegedHelper/`; zero matches
outside doc comments explicitly stating it's not used yet). No elevated
privileges are exercised anywhere in this app today.

What exists instead: `PrivilegedHelperClientProtocol`
(`Packages/PrivilegedHelperXPC/Sources/PrivilegedHelperXPC/MockPrivilegedHelper.swift`)
— a Swift-native `async`/`await` seam mirroring the four operations the
`@objc`, reply-closure-based `PrivilegedHelperProtocol` exposes for the
real XPC wire format — and `MockPrivilegedHelper`, an `actor` that
simulates those operations entirely in memory (quarantine records a path
in a dictionary rather than moving anything, restore consumes a receipt,
maintenance tasks return canned outcomes for a small fixed ID set).
App-side code depends on `PrivilegedHelperClientProtocol`, never on the
mock's concrete type or on `PrivilegedHelperProtocol` directly, so a real
XPC-backed conformer can replace `MockPrivilegedHelper` later with zero
call-site changes — only a change at the dependency-injection root.

Real implementation work still needed, once there's a reason to build it:
an executable target under `PrivilegedHelper/` (`NSXPCListener` exporting
`PrivilegedHelperProtocol` over `PrivilegedHelperConstants.machServiceName`),
`SMAppService.daemon(plistName:)` registration from the Developer ID app
only, a real `NSXPCConnection`-backed `PrivilegedHelperClientProtocol`
conformer, and — critically — the helper's own independent
`SafetyRules.Denylist` re-check before touching disk, so a compromised or
buggy app process can't abuse elevated access (this is a structural
requirement already documented on `PrivilegedHelperProtocol` itself, not
new).

## Release pipeline

Two tracks, deliberately kept separate — one works today, one is
scaffolding for later.

**Track A — local, working now.** `Scripts/ci.sh` runs `xcodegen generate`
+ `xcodebuild build` for `MCleanPro-DeveloperID` (Debug) + `swift test`
across every package, with a clear pass/fail summary and non-zero exit on
any failure; verified end-to-end. An opt-in git pre-push hook
(`Scripts/install-git-hooks.sh`) runs it before every push. `Scripts/release.sh`
bumps a semantic version (git tags `vX.Y.Z`, `v0.1.0` fallback baseline —
no tag exists yet, a maintainer creates the first one deliberately),
regenerates `CHANGELOG.md` from Conventional Commit messages since the
last tag, builds `MCleanPro-DeveloperID` in Release, and packages a
`.dmg` under `dist/` (gitignored) via `hdiutil`. It inspects the actual
`codesign` output and only drops the `-unsigned-local-build-only`
filename suffix for a genuine Developer ID Application signature — see
"Code signing: current status" below for why every build today keeps that
suffix, honestly. Verified end-to-end for real (not just self-reported):
built, packaged, `hdiutil verify`d as VALID.

Commits follow [Conventional Commits](https://www.conventionalcommits.org/)
from this point forward — existing history is not being rewritten.

**Track B — dormant scaffolding, not yet active.**
`.github/workflows/ci.yml`/`release.yml` use normal GitHub Actions
triggers (push/PR; push tags `v*`) but have nowhere to fire until this
repo is pushed to a GitHub remote — see README.md for why no remote exists
yet by design. `release.yml`'s signing/notarization section is explicitly
marked `[NON-FUNCTIONAL]` (`if: false`, echo-only steps) and references
five secrets purely via `${{ secrets.NAME }}` syntax — no real or
realistic-looking credential material anywhere. **Neither workflow ever
auto-publishes anything** — `release.yml`'s happy path uploads the same
honest unsigned `.dmg` as a workflow-run artifact, never a GitHub Release,
never an external upload.

### Code signing: current status

No paid Apple Developer Program membership / Developer ID Application
certificate exists, and **none is needed today** — Xcode already signs
local builds automatically with the personal free-tier team, which is
sufficient to build and run this app on the machine that built it. A
Developer ID certificate only becomes necessary if the app needs to run
on a different Mac or be shared with someone else (Gatekeeper requires a
recognized signature + notarization for that). `release.sh` makes this
distinction honest in the artifact's filename itself rather than a doc
comment nobody reads at release time. See `RELEASE.md` for the full
local-build-vs-distributable-release distinction.

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
