import Foundation
import CoreScanEngine

/// Adapts `InstalledAppsInspector` to `CoreScanEngine.Detector` so the app
/// layer can fold "installed applications" into the same scan
/// pipeline/UI plumbing as every other detector, per PROMPT MASTER §5.4.
///
/// Unlike most `Detector`s, this isn't "cleanable junk" — it's an inventory
/// listing. `ScanItem.reason` is deliberately descriptive rather than a
/// removal suggestion, and nothing about this type implies these items are
/// offered for quarantine (that's a UI-layer decision, likely gated behind
/// an explicit "Uninstaller" flow, not this scan).
public struct InstalledAppsDetector: Detector {
    public let id = "poweruser.apps.installed"
    public let displayName = "Installed Applications"
    public let category: DetectorCategory = .powerUser

    private let inspector: InstalledAppsInspector

    public init(inspector: InstalledAppsInspector = InstalledAppsInspector()) {
        self.inspector = inspector
    }

    public func scan(context: ScanContext) async throws -> [ScanItem] {
        let directories = context.roots.isEmpty
            ? InstalledAppsInspector.defaultSearchDirectories()
            : context.roots
        let apps = await inspector.scanApplications(in: directories)

        return apps.map { app in
            var reason = app.name
            if let bundleIdentifier = app.bundleIdentifier {
                reason += " (\(bundleIdentifier))"
            }
            if let shortVersion = app.shortVersion {
                reason += ", version \(shortVersion)"
            }
            reason += " — inventory entry from the installed-applications listing, not a cleanup suggestion."

            return ScanItem(
                path: app.path,
                sizeBytes: app.sizeBytes,
                sourceDetectorID: id,
                category: "Installed application",
                lastUsed: app.lastUsed,
                reason: reason
            )
        }
    }
}
