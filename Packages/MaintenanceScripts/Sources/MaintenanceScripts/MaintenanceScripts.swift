/// `MaintenanceScripts` — PROMPT MASTER §5.1's "Maintenance scripts": flush
/// DNS, rebuild the Spotlight index, verify the startup disk (the honest
/// modern equivalent of "repair permissions"), and clear the font cache.
///
/// Each task is a fixed, reviewed, hardcoded command invocation, described
/// to the user before it can be triggered, and only ever run from an
/// explicit user tap — see `MaintenanceTask`'s doc comment for the full
/// rationale on why this doesn't go through `SafetyRules`/quarantine, and
/// `MaintenanceScriptsRegistry` for how the app layer lists every task.
public enum MaintenanceScriptsModule {}
