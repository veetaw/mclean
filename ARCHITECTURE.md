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

## Open checkpoints (must not be resolved without the user)

These come directly from the product spec (PROMPT MASTER §10) and are
tracked here so they aren't silently decided by an agent:

1. **Local HTTP server library for `RemoteControlServer`** — trade-off
   between a minimal hand-rolled `Network.framework` server, a lightweight
   library (e.g. Swifter), or SwiftNIO. Not yet decided; the package has no
   HTTP dependency declared.
2. **Any code path that performs a real deletion** (even into quarantine)
   against non-test data. `SafetyRules.QuarantineManaging` is a protocol
   only; no conforming type touches real paths yet.
3. **Any system permission not already listed in the product spec**, if one
   turns out to be needed during implementation.
4. **Final format of the safety rule file** (`SAFETY_RULES.md` / the YAML
   schema). `RuleSetDraft.swift` in the `SafetyRules` package sketches a
   proposal, explicitly marked draft/pending review.

## Trade-offs to be documented here as they're made

- HTTP vs. local TLS for the remote-control server (currently: HTTP + token
  auth, LAN-only, documented as an accepted trade-off pending a future
  mkcert-style local TLS option — see PROMPT MASTER §5.6).
- SPM packages declare `platforms: [.macOS(.v15)]` as a conservative build
  floor; the actual app targets will pin macOS 26 (Tahoe)+ as the real
  minimum deployment target, per the product spec.
