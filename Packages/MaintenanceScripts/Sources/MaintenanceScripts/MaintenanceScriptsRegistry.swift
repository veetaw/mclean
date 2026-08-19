/// Convenience registry so the app layer can list every available
/// maintenance task in one call:
///
/// ```swift
/// for task in MaintenanceScriptsRegistry.all() {
///     // show task.title / task.description / task.requiresAdministratorPrivileges,
///     // and only call `await task.run()` from an explicit user tap.
/// }
/// ```
///
/// See `MaintenanceTask` for the interface every task below implements.
public enum MaintenanceScriptsRegistry {
    /// One instance of every `MaintenanceScripts` task.
    public static func all() -> [any MaintenanceTask] {
        [
            FlushDNSCacheTask(),
            RebuildSpotlightIndexTask(),
            VerifyStartupDiskTask(),
            ClearFontCacheTask()
        ]
    }
}
