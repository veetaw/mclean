# MClean Pro

A native macOS app (SwiftUI, Liquid Glass) that combines general system
cleaning with a deep **Developer Tools** module: it finds cache and build
artifacts left behind by common dev toolchains (Python, Node, Rust, Go,
Ruby, Java/Gradle, Docker, Xcode, Android, ...) and helps you reclaim disk
space safely.

> **Status:** early scaffolding. This repository currently contains the
> module structure, shared protocols, and safety-critical interfaces. Most
> packages are placeholders — see `ARCHITECTURE.md` for what's built vs.
> planned, and the per-phase status reports in git history / conversation
> for the current build plan.

## Non-negotiable safety principles

- Nothing is ever deleted without explicit user confirmation, except items
  matching a versioned, user-inspectable `safe-auto` rule.
- A hardcoded, non-configurable denylist protects system-critical paths —
  it cannot be bypassed from any UI or settings file.
- Every deletion goes through a reversible quarantine (7-day default)
  before anything is permanently removed.
- Every scan supports dry-run (show what would happen, touch nothing).

See `SAFETY_RULES.md` for the full policy and how to extend it.

## Repository layout

```
App/                    Xcode app targets (App Store + Developer ID)
Packages/                Swift Package Manager modules (see ARCHITECTURE.md)
PrivilegedHelper/         SMAppService privileged helper target
RemoteWebApp/             Static web app for LAN remote control
Scripts/                  Build / notarization / dev scripts
```

## Building

Each package under `Packages/` builds independently:

```sh
cd Packages/CoreScanEngine && swift build
```

The full app (Xcode project/workspace tying the packages + App targets
together) has not been generated yet — see `ARCHITECTURE.md` for the
planned target setup (`MCleanPro-AppStore`, `MCleanPro-DeveloperID`).

## License

MIT — see `LICENSE`.
