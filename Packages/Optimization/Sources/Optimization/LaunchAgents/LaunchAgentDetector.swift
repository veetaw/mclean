import Foundation
import CoreScanEngine

/// Finds Launch Agent plists under the two locations this build can safely
/// enumerate without a privileged helper: `~/Library/LaunchAgents` (this
/// user only) and `/Library/LaunchAgents` (every user on the machine, but
/// still admin-writable, unlike root-owned `/Library/LaunchDaemons`).
///
/// Deliberately **not** scanned: `/Library/LaunchDaemons` and
/// `/System/Library/LaunchAgents` — both are root-owned/system-critical,
/// and this build has no `PrivilegedHelper` executable yet to safely touch
/// them (see `ARCHITECTURE.md`'s module graph: `PrivilegedHelperXPC` has no
/// concrete helper target scaffolded).
///
/// ## `DetectorCategory` gap — flagged during implementation, since fixed
///
/// The implementing agent correctly flagged that `CoreScanEngine
/// .DetectorCategory` had no case naming this module, while two other
/// still-unbuilt PROMPT MASTER §5.1 sub-features (Uninstaller, Privacy)
/// already had dedicated cases despite being unimplemented at the time —
/// strong evidence the omission was accidental. A `.optimization` case was
/// added to `DetectorCategory` and this detector migrated to it during
/// review, rather than shipping with the `.systemJunk` stand-in.
///
/// Strictly read-only — see `CoreScanEngine.Detector`. This type never
/// disables, deletes, or modifies a Launch Agent; "disabling" one (in the
/// real app) means quarantining its plist file via the existing
/// `SafetyRules.FileSystemQuarantineManager` flow, entirely outside this
/// package. Every `ScanItem` this produces still passes through
/// `SafetyRules.SafetyClassifier` at the app's single chokepoint before
/// ever being offered for quarantine.
public struct LaunchAgentDetector: Detector {
    public let id = "optimization.launch-agents"
    public let displayName = "Launch Agents"
    public let category: DetectorCategory = .optimization

    private let userLaunchAgentsPath: String
    private let systemLaunchAgentsPath: String

    /// - Parameters:
    ///   - userLaunchAgentsPath: Defaults to `~/Library/LaunchAgents`;
    ///     overridable for tests.
    ///   - systemLaunchAgentsPath: Defaults to `/Library/LaunchAgents`;
    ///     overridable for tests.
    public init(
        userLaunchAgentsPath: String = NSHomeDirectory() + "/Library/LaunchAgents",
        systemLaunchAgentsPath: String = "/Library/LaunchAgents"
    ) {
        self.userLaunchAgentsPath = userLaunchAgentsPath
        self.systemLaunchAgentsPath = systemLaunchAgentsPath
    }

    public func scan(context: ScanContext) async throws -> [ScanItem] {
        var items: [ScanItem] = []
        let locations: [(path: String, scope: LaunchAgentPlist.Scope)] = [
            (userLaunchAgentsPath, .user),
            (systemLaunchAgentsPath, .system)
        ]

        for location in locations {
            if Task.isCancelled { break }
            for plistPath in LaunchAgentPlistParser.discoverPlistPaths(in: location.path) {
                if Task.isCancelled { break }
                // A file that fails to parse is skipped, not fatal — one
                // malformed plist must never abort the rest of the scan.
                guard let parsed = LaunchAgentPlistParser.parse(
                    contentsOfFile: plistPath,
                    scope: location.scope
                ) else {
                    continue
                }
                items.append(scanItem(for: parsed))
            }
        }

        return items
    }

    private func scanItem(for plist: LaunchAgentPlist) -> ScanItem {
        let scopeLabel = plist.scope == .user ? "user" : "system-wide (all users)"
        var reasonParts: [String] = []

        if let label = plist.label {
            reasonParts.append("Launch Agent '\(label)'")
        } else {
            reasonParts.append(
                "Launch Agent with no 'Label' key — technically invalid per launchd.plist(5), but present on disk"
            )
        }
        if let program = plist.program {
            reasonParts.append("launches '\(program)'")
        }
        reasonParts.append(
            "registered \(scopeLabel), so launchd starts it for \(plist.scope == .user ? "this user" : "every user on this Mac") whenever the job is loaded"
        )
        if plist.runAtLoad {
            reasonParts.append("RunAtLoad is set, so it launches automatically at every login — a candidate that may affect startup time, not a measured timing result")
        }
        if plist.keepAlive {
            reasonParts.append("KeepAlive is set, so launchd relaunches it if it exits")
        }
        reasonParts.append(
            "Inventory only — MClean Pro never disables or deletes a Launch Agent here; \"disabling\" one means quarantining this plist file through the app's normal review flow"
        )

        return ScanItem(
            path: plist.path,
            sizeBytes: OptimizationFS.fileSize(plist.path),
            sourceDetectorID: "\(id).\(plist.scope.rawValue)",
            category: "Launch Agent — \(scopeLabel)",
            lastUsed: OptimizationFS.modificationDate(plist.path).map {
                LastUsedEvidence(date: $0, source: .filesystemMTime)
            },
            reason: reasonParts.joined(separator: "; ") + "."
        )
    }
}
