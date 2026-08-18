# Architecture

## Module graph

```
CoreScanEngine  (no deps)
  ├─ SafetyRules            (depends on CoreScanEngine)
  ├─ DevToolsDetectors      (depends on CoreScanEngine)
  ├─ MobileDevDetectors     (depends on CoreScanEngine)
  └─ RemoteControlServer    (depends on CoreScanEngine, SafetyRules)  [blocked, see below]

PrivilegedHelperXPC (no deps)
  └─ PowerUserInspectors    (depends on CoreScanEngine, PrivilegedHelperXPC)

SafetyRules
  └─ MenuBarAgent           (depends on CoreScanEngine, SafetyRules)

UIDesignSystem   (no deps)
VirusTotalClient (no deps)
```

`MainAppUI` (not yet scaffolded) will depend on `UIDesignSystem` plus every
other module to assemble the SwiftUI app. `PrivilegedHelper` (the actual
executable target registered via `SMAppService`) depends only on
`PrivilegedHelperXPC` for the protocol definition, kept intentionally
narrow since it runs with elevated privileges.

## Status by module (as of initial scaffolding)

| Module | Status |
|---|---|
| CoreScanEngine | Core protocols + concurrent `ScanEngine` actor implemented. Read-only by construction — no deletion code path exists here. |
| SafetyRules | `SafetyVerdict`, hardcoded `Denylist` (path/pattern matching), and the `QuarantineManaging` **protocol** are implemented. No concrete quarantine/deletion implementation yet — gated on checkpoint 2 (see below). Rule file format is a **draft**, gated on checkpoint 4. |
| PrivilegedHelperXPC | XPC protocol defined. No helper executable or entitlements yet. |
| VirusTotalClient | Protocol + rate-limit accounting implemented. No network layer yet. |
| DevToolsDetectors, MobileDevDetectors, PowerUserInspectors, MenuBarAgent, UIDesignSystem, RemoteControlServer | Placeholder targets only (compile, no functionality). Scoped for later phases. |
| App/, PrivilegedHelper/, RemoteWebApp/, Scripts/ | Directory scaffolding only. |

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
