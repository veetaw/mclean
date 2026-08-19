/// `Optimization` — PROMPT MASTER §5.1: "gestione login items/launch
/// agents, elenco processi che rallentano l'avvio."
///
/// Three sub-areas, each scoped to what's genuinely achievable from an
/// unprivileged process with only public/documented APIs:
///
/// 1. **Launch Agent / Login Item inventory** — `LaunchAgentDetector`
///    (a `CoreScanEngine.Detector`) enumerates plists under
///    `~/Library/LaunchAgents` and `/Library/LaunchAgents` only — see its
///    doc comment for why `/Library/LaunchDaemons` and
///    `/System/Library/LaunchAgents` are out of scope for this build, and
///    for the `DetectorCategory` gap flagged there.
/// 2. **Login items listing** — `LoginItemsInspector`: this app's own
///    `SMAppService` status (exact), plus a best-effort, clearly-labeled
///    approximation from `RunAtLoad`-flagged Launch Agents and an optional
///    AppleScript/System Events supplement. See its doc comment for
///    exactly what a *complete* login items list would require and why
///    this build doesn't attempt it.
/// 3. **Startup-impact report** — `StartupImpactReporter`: a static,
///    explicitly-unmeasured "candidates that may affect startup time" list
///    derived from `RunAtLoad`/`KeepAlive`, never a timing result.
///
/// Every component here is strictly read-only. Nothing in this package
/// disables, deletes, or modifies a Launch Agent or login item —
/// "disabling" one, in the real app, means quarantining its plist file via
/// `SafetyRules.FileSystemQuarantineManager`, entirely outside this
/// package. See `OptimizationRegistry` for how the app layer wires
/// `LaunchAgentDetector` into `CoreScanEngine.ScanEngine`.
public enum OptimizationModule {}
