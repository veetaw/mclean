/// Supplies the live-ish stats the menu bar popover displays. Kept as a
/// protocol so `MenuBarPopoverViewModel` can be driven by a fake in tests.
public protocol SystemStatsProviding: Sendable {
    func snapshot() async -> SystemStatsSnapshot
}
