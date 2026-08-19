# Architecture

## Module graph

```
CoreScanEngine  (no deps)
  ├─ SafetyRules            (depends on CoreScanEngine)
  ├─ DevToolsDetectors      (depends on CoreScanEngine)
  ├─ MobileDevDetectors     (depends on CoreScanEngine)
  └─ RemoteControlServer    (depends on CoreScanEngine, SafetyRules, Swifter)

PrivilegedHelperXPC (no deps)
  └─ PowerUserInspectors    (depends on CoreScanEngine, PrivilegedHelperXPC)

SafetyRules
  └─ MenuBarAgent           (depends on CoreScanEngine, SafetyRules)

UIDesignSystem   (no deps)
VirusTotalClient (no deps)

MainAppUI (depends on UIDesignSystem + every module above)
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
| SafetyRules | `SafetyVerdict`, hardcoded `Denylist`, `SafetyClassifier`, and the **real** `FileSystemQuarantineManager` (reversible move-based quarantine, JSON manifest, independent denylist re-check). Rule file format still a **draft** (checkpoint 4). **14 tests.** |
| PrivilegedHelperXPC | XPC protocol defined. No helper executable or entitlements yet. **1 test.** |
| VirusTotalClient | Hash-check-first protocol + rate limiter. No concrete network implementation yet. **1 test.** |
| DevToolsDetectors | 10 toolchain detectors (Python/Node/Rust/Go/Ruby/Java/Docker/Xcode/Homebrew/editors), all read-only. **44 tests.** |
| MobileDevDetectors | Android (AVD/SDK/Studio/Gradle-wrapper) + iOS (Simulator/CocoaPods/Fastlane) detectors. **30 tests.** |
| PowerUserInspectors | Installed apps, TCC listing (read-only, no revocation path), config file explorer (backup-before-write, always), per-language package explorer, JSON system report (PDF export deferred). **70 tests.** |
| MenuBarAgent | `NSStatusItem` controller, FSEvents-based background monitoring, low-disk-space notifications, scheduled health check, system stats. **37 tests.** |
| UIDesignSystem | Liquid Glass tokens/components (cards, buttons, safety badges, scan-result rows). **7 tests.** |
| RemoteControlServer | Swifter-based LAN HTTP server, Bonjour advertisement, two-phase pairing, approval workflow (single quarantine call site, defense-in-depth verdict re-check). **27 tests.** |
| RemoteWebApp | Vanilla HTML/CSS/JS mobile client matching the server's API contract (documented in `RemoteWebApp/README.md`). No camera QR scanning yet. |
| MainAppUI | `Capabilities`/`BuildFlavor` registry, `AppEnvironment` composition root, full `NavigationSplitView` app (Dashboard, Developer Tools, Mobile Dev, Power User, Quarantine, Remote Control, Settings, onboarding). **14 tests.** |
| App/ | `project.yml` (xcodegen) generating `MCleanPro-AppStore` (sandboxed) and `MCleanPro-DeveloperID` (unsandboxed, hardened runtime) — both verified to build with `xcodebuild`. |
| PrivilegedHelper/, Scripts/ | Directory scaffolding only — no executable/build scripts yet. |

**Known gap:** the core "System Junk" cleaning module from the product
spec (§5.1 — system/user cache cleanup, trash bins, large & old files
finder, duplicate finder, uninstaller, privacy cleaner, maintenance
scripts, Space Lens, shredder) has no dedicated package. `MainAppUI`'s
Dashboard shows an honest placeholder for it rather than faking results.
This is the single largest remaining scope item from the original spec.

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
4. **Final format of the safety rule file** — still a **draft**, pending
   review of the open questions listed at the bottom of `SAFETY_RULES.md`.
   Not blocking Phase 1: `Denylist` and the quarantine mechanism don't
   depend on the rule-file format being finalized.

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
