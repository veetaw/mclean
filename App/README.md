# App

Xcode project/workspace scaffolding not yet generated — planned for the
`Agent:MainAppUI` phase (Phase 2), once the modules it assembles
(`UIDesignSystem` + all feature packages) have real implementations.

- `AppStoreTarget/` — sandboxed build, gated via the `Capabilities` registry
  and `#if APPSTORE`.
- `DeveloperIDTarget/` — full-featured, notarized, hardened runtime build.

Both targets share the same `Packages/*` sources.
