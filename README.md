# MClean Pro

A native macOS app (SwiftUI, Liquid Glass) that combines general system
cleaning with a deep **Developer Tools** module: it finds cache and build
artifacts left behind by common dev toolchains (Python, Node, Rust, Go,
Ruby, Java/Gradle, Docker, Xcode, Android, ...) and helps you reclaim disk
space safely.

> **Status:** every module in the product spec's §5.1 scope is implemented
> and tested at MVP level (487 tests passing across 21 packages) — System
> Junk, Trash Bins, Large & Old Files, Duplicates, Uninstaller,
> Optimization, Privacy, Maintenance Scripts, Space Lens, and a secure
> Shredder (the one deliberate exception to the reversible-quarantine
> flow — see `ARCHITECTURE.md`). `VirusTotalClient` has a real network
> implementation now too. The `MCleanPro-DeveloperID` app target builds
> and passes its full test suite via one command, `Scripts/ci.sh`.
>
> **`MCleanPro-AppStore` is deliberately paused**, not missing — its code
> (sandbox `Capabilities` gating, the limitation banner, entitlements)
> stays in the repo untouched and builds on demand (see below); it's just
> not part of the active `ci.sh`/`release.sh` pipeline right now, to keep
> iteration fast. What's still genuinely unbuilt: a real `PrivilegedHelper`
> daemon (a documented in-memory mock stands in today — see
> `ARCHITECTURE.md`), and real code signing/notarization for distributing
> outside this Mac (see `RELEASE.md` — not needed for personal use on your
> own machine). See `ARCHITECTURE.md`'s status table for the module-by-
> module detail and `TESTING.md` for the manual checklist items that can't
> be automated.

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
PrivilegedHelper/         SMAppService privileged helper target (mock stub only today)
RemoteWebApp/             Static web app for LAN remote control
Scripts/                  ci.sh / release.sh / git hooks (see RELEASE.md)
.github/workflows/        Dormant GitHub Actions scaffolding (see RELEASE.md)
```

## Building

The one-command way (requires [xcodegen](https://github.com/yonaskolb/XcodeGen), `brew install xcodegen`):

```sh
Scripts/ci.sh
```

Regenerates the Xcode project, builds `MCleanPro-DeveloperID` (Debug), and
runs every package's test suite — the same thing an opt-in pre-push hook
(`Scripts/install-git-hooks.sh`) runs before every push. See `Scripts/README.md`.

Each package under `Packages/` also builds and tests independently:

```sh
cd Packages/CoreScanEngine && swift build && swift test
```

`MCleanPro-AppStore` is deliberately excluded from `ci.sh` (paused, not
broken — see the status note above) but still builds manually any time:

```sh
cd App
xcodegen generate
xcodebuild -project MCleanPro.xcodeproj -scheme MCleanPro-AppStore -configuration Debug build
```

Local builds skip code signing (`CODE_SIGN_IDENTITY: "-"`) so this works
without an Apple Developer Team ID — that's a dev convenience, not a
notarization setup. `App/MCleanPro.xcodeproj` is generated and gitignored;
regenerate it any time with `xcodegen generate`, don't hand-edit it.

## Building a release

```sh
Scripts/release.sh patch   # or: minor / major
```

Bumps the version, regenerates `CHANGELOG.md`, builds `MCleanPro-DeveloperID`
in Release, and packages a `.dmg` under `dist/` (gitignored). The filename
tells you honestly whether it's a real distributable build or a
`-unsigned-local-build-only` one — see `RELEASE.md` for what that
distinction means and what (if anything) you need to do about it before
sharing a build with someone else.

## Testing

See `TESTING.md` for the full picture: what's covered by the 487 automated
tests, and the manual checklist for the parts that aren't (remote pairing,
permission onboarding, Shredder, System Junk).

## License

MIT — see `LICENSE`.
