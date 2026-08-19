import Foundation

/// Verifies the startup volume's filesystem — the honest, modern
/// replacement for the old "Repair Disk Permissions" feature.
///
/// ## Why this isn't "Repair Permissions"
///
/// Classic Disk Utility's "Repair Disk Permissions" compared files against
/// package-receipt "bill of materials" (BOM) manifests and reset ownership/
/// mode bits that had drifted. That entire model was **removed in OS X
/// 10.11 (El Capitan)**: System Integrity Protection and, later, the sealed
/// System volume mean the files that mattered are no longer writable even
/// by root, and app installers largely stopped using the receipt-based
/// installer flow this depended on. There is no macOS API or CLI tool
/// today that does what "Repair Permissions" used to do, because the thing
/// it fixed can no longer happen the way it used to.
///
/// Rather than faking a "Repair Permissions" button that runs some command
/// and reports success while not actually repairing anything meaningful,
/// this task is honestly relabeled to what current macOS actually offers in
/// the same neighborhood: **`diskutil verifyVolume /`**, which checks the
/// startup volume's filesystem structure for problems. This is read-only —
/// it verifies, it does not repair, and needs no administrator privileges
/// — matching modern Disk Utility's own First Aid "Verify" behavior. If
/// verification finds an actual problem, the description tells the user to
/// open Disk Utility and run First Aid's repair from there, since repairing
/// a live-mounted volume's filesystem is not something this task attempts.
public struct VerifyStartupDiskTask: MaintenanceTask {
    public let id = "maintenance.verify-startup-disk"
    public let title = "Verify Startup Disk"
    public let description = """
    Checks your startup disk's filesystem for problems by running \
    "diskutil verifyVolume /". This is the modern, honest equivalent of the \
    old "Repair Disk Permissions" feature — that feature was removed in \
    macOS 10.11 (El Capitan) because System Integrity Protection and the \
    sealed system volume made permission drift the kind of thing it used \
    to fix no longer possible. This check is read-only (it verifies, it \
    does not repair) and needs no administrator password. If it reports a \
    problem, open Disk Utility and run First Aid to repair it — that \
    requires unmounting the disk, which isn't safe to do from a running app.
    """
    public let requiresAdministratorPrivileges = false

    public init() {}

    public func run(using runner: MaintenanceCommandRunning) async -> MaintenanceTaskResult {
        let outcome = await runner.run(
            executable: "/usr/sbin/diskutil",
            arguments: ["verifyVolume", "/"],
            timeout: maintenanceCommandTimeout
        )

        guard outcome.succeeded else {
            return MaintenanceTaskResult(
                taskID: id,
                outcome: .failure,
                summary: "diskutil verifyVolume \(outcome.failureDescription)",
                output: outcome.combinedOutput
            )
        }

        return MaintenanceTaskResult(
            taskID: id,
            outcome: .success,
            summary: "Startup disk verified — no repair was performed (verification is read-only).",
            output: outcome.combinedOutput
        )
    }
}
