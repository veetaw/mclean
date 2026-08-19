/// Placeholder so this target builds before `Agent:MaintenanceScripts`
/// (Phase 6) fills it in — flush DNS, rebuild Spotlight index, repair
/// permissions, clear font cache. Explicit, described, never automatic.
/// See PROMPT MASTER §5.1.
public enum MaintenanceScriptsModule {
    public static let placeholder = true
}
