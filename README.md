# MClean Pro

A native macOS app (SwiftUI, Liquid Glass) that combines general system
cleaning with a deep **Developer Tools** module: it finds cache and build
artifacts left behind by common dev toolchains (Python, Node, Rust, Go,
Ruby, Java/Gradle, Docker, Xcode, Android, ...) and helps you reclaim disk
space safely.

> **Status:** all planned modules are implemented and tested (246 tests
> passing across 11 packages), and both app targets (`MCleanPro-AppStore`,
> `MCleanPro-DeveloperID`) build successfully via `xcodegen`. What's *not*
> built yet: the core "System Junk" cleaners (§5.1 of the product spec —
> trash bins, large/old files, duplicates), a concrete `VirusTotalClient`
> network implementation, the `PrivilegedHelper` executable itself, and
> real code-signing/notarization. See `ARCHITECTURE.md`'s status table for
> the module-by-module detail and `TESTING.md` for the manual checklist
> items that can't be automated (pairing flow, permission onboarding).

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

Each package under `Packages/` builds and tests independently:

```sh
cd Packages/CoreScanEngine && swift build && swift test
```

To build the actual app (requires [xcodegen](https://github.com/yonaskolb/XcodeGen), `brew install xcodegen`):

```sh
cd App
xcodegen generate
xcodebuild -project MCleanPro.xcodeproj -scheme MCleanPro-DeveloperID -configuration Debug build
xcodebuild -project MCleanPro.xcodeproj -scheme MCleanPro-AppStore -configuration Debug build
```

Local builds skip code signing (`CODE_SIGN_IDENTITY: "-"`) so this works
without an Apple Developer Team ID — that's a dev convenience, not a
notarization setup. `App/MCleanPro.xcodeproj` is generated and gitignored;
regenerate it any time with `xcodegen generate`, don't hand-edit it.

## Testing

See `TESTING.md` for the full picture: what's covered by the 246 automated
tests, and the manual checklist for the parts that aren't (remote pairing,
permission onboarding).

## License

MIT — see `LICENSE`.
