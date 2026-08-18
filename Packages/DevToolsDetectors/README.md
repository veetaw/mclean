# DevToolsDetectors

Implements `CoreScanEngine.Detector` for each developer toolchain in PROMPT
MASTER §5.2: Python, Node/JS, Rust, Go, Ruby, Java/JVM, Docker, Xcode,
Homebrew, and editor/IDE caches. Strictly read-only — every detector only
finds and evaluates "last real use"; nothing here ever deletes, moves, or
modifies anything.

One file per toolchain under `Sources/DevToolsDetectors/`:

- `PythonDetector.swift` — pip cache, conda/mamba package cache, orphaned
  virtualenvs (via `.project` markers where present, best-effort mtime
  heuristic otherwise), stray `__pycache__`, Jupyter cache.
- `NodeDetector.swift` — stale `node_modules` (configurable threshold,
  default 90 days; notes but does not block on an active `.git` in the
  parent project), npm/Yarn/pnpm caches, Turborepo/webpack/vite caches.
- `RustDetector.swift` — Cargo registry cache, stale per-project `target/`.
- `GoDetector.swift` — module cache (`GOPATH`/`GOCACHE`-aware) and build cache.
- `RubyDetector.swift` — gem caches, unused rbenv/rvm versions (best-effort).
- `JavaDetector.swift` — Gradle cache, Maven local repository, unused
  SDKMAN candidates.
- `DockerDetector.swift` — dangling images/orphan volumes/build cache via
  the `docker` CLI when present; returns no items (never throws) when Docker
  isn't installed. Every finding's `reason` carries an explicit warning.
- `XcodeDetector.swift` — DerivedData, old Archives, Simulator runtimes,
  old iOS/watchOS/tvOS DeviceSupport folders.
- `HomebrewDetector.swift` — Homebrew's own download cache as normal scan
  items, plus `HomebrewDetector.guidedActions` (`DevToolsGuidedAction`) for
  `brew cleanup`/`brew autoremove`, which are surfaced as suggested commands
  rather than executed.
- `EditorDetector.swift` — JetBrains caches, VS Code cache directories, and
  best-effort-stale VS Code extensions (by mtime; VS Code doesn't record a
  real per-extension last-used date on disk).

`DevToolsDetectorRegistry.all()` (in `DevToolsDetectors.swift`) returns one
instance of every detector above for the app layer to register with
`ScanEngine` in a single call.

Shared, internal-only support code lives under `Sources/DevToolsDetectors/Support/`:
filesystem helpers (`DevToolsFS`), an external-process runner with a hard
timeout used only by `DockerDetector` (`ExternalProcess`), home-directory
resolution from `ScanContext.roots` (`HomeDirectories`), and the guided
action model (`DevToolsGuidedAction`).

Tests under `Tests/DevToolsDetectorsTests/` build a throwaway sandbox "home
directory" per test (via `TempHome`) rather than depending on the real
machine having any of these toolchains installed; `DockerDetectorTests`
points a sandboxed `PATH` at a fake `docker` shell script to exercise the
CLI-parsing logic without requiring Docker itself.

**Deferred / follow-up:** Spotlight-based `LastUsedEvidence.spotlightLastUsedDate`
(via `mdls`/`NSMetadataItem`) is not implemented — evidence is currently
`manifestOrLockfileMTime` where a stronger signal exists (lockfiles,
`Cargo.toml`), falling back to `filesystemMTime`. Adding Spotlight support
is tracked as a follow-up rather than a partial/fragile implementation.
