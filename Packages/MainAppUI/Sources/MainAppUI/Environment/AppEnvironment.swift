import AppKit
import CoreScanEngine
import DevToolsDetectors
import Foundation
import MenuBarAgent
import MobileDevDetectors
import Observation
import PowerUserInspectors
import PrivilegedHelperXPC
import RemoteControlServer
import SafetyRules
import VirusTotalClient

/// Single composition root shared by both Xcode app targets
/// (`MCleanPro-AppStore`, `MCleanPro-DeveloperID`). Constructs and owns the
/// real instances of every backend package this app assembles, so neither
/// target's `@main App` entry point duplicates wiring — each just does
/// `AppEnvironment.bootstrap()` and hands the result to `ContentView`.
///
/// `@MainActor`/`@Observable` because SwiftUI views read its properties
/// directly (paired devices, remote control running state, etc.) and it
/// owns `@MainActor`-isolated types (`MenuBarController`).
@MainActor
@Observable
public final class AppEnvironment {
    public let capabilities: Capabilities

    public let scanEngine: ScanEngine
    public let safetyClassifier: SafetyClassifying
    public let quarantineManager: QuarantineManaging
    public let scanSnapshotStore: ScanSnapshotStore

    /// Non-nil when `official_rules.yaml`'s integrity check failed, or
    /// either rule file failed to parse — surfaced as a visible warning in
    /// `SettingsView` per checkpoint 4's closure. `nil` means everything
    /// loaded cleanly (the common case).
    public let safetyRulesIntegrityWarning: String?

    /// The only supported way this app changes a TCC grant: opens the
    /// relevant System Settings pane. See `PowerUserInspectors.TCCSettingsPaneOpener`.
    public let tccSettingsPaneOpener = TCCSettingsPaneOpener()

    /// `nil` in the App Store flavor — see `Capabilities.canRunRemoteControlServer`.
    /// Constructed at `init` time (not started) when the capability is on;
    /// starting/stopping the listener is a separate, explicit user action
    /// from the Remote Control settings screen, never automatic.
    public private(set) var remoteControlServer: RemoteControlServer?

    /// `nil` until `activateMenuBarAgent()` is called by the app's entry
    /// point. Deliberately **not** constructed by `init`/`bootstrap()`:
    /// `NSStatusBar`/`NSPopover` want a live `NSApplication` run loop, which
    /// a headless `swift test` invocation doesn't have. Keeping menu-bar
    /// activation as an explicit, separate step is what keeps the rest of
    /// this type's composition testable without live AppKit (see
    /// `Tests/MainAppUITests/AppEnvironmentTests.swift`).
    public private(set) var menuBarController: MenuBarController?

    /// `nil` until a real `VirusTotalClient` conformer exists (see that
    /// package's doc comment — protocol only, no concrete implementation
    /// yet) and the user supplies an API key. UI should treat this as
    /// "feature visible, not configured" per PROMPT MASTER §5.7, not hide
    /// the section outright.
    public var virusTotalClient: VirusTotalClient?

    public init(
        capabilities: Capabilities = .current,
        quarantineRootURL: URL? = nil,
        userRulesDirectory: URL? = nil
    ) {
        self.capabilities = capabilities

        let engine = ScanEngine()
        self.scanEngine = engine
        let loadedRules = RuleFileLoader.load(userRulesDirectory: userRulesDirectory)
        self.safetyClassifier = SafetyClassifier(rules: loadedRules.rules, integrityWarning: loadedRules.warning)
        self.safetyRulesIntegrityWarning = loadedRules.warning
        let quarantine = FileSystemQuarantineManager(quarantineRootURL: quarantineRootURL)
        self.quarantineManager = quarantine
        self.scanSnapshotStore = ScanSnapshotStore()
        self.virusTotalClient = nil

        if capabilities.canRunRemoteControlServer {
            self.remoteControlServer = RemoteControlServer(
                scanSnapshotProvider: scanSnapshotStore,
                quarantineManager: quarantine
            )
        } else {
            self.remoteControlServer = nil
        }
    }

    /// Constructs an `AppEnvironment` and registers every detector package
    /// this app ships with the shared `ScanEngine`, awaiting completion
    /// before returning — the async factory call sites (both `@main App`
    /// entry points, and tests) should use instead of `init` directly
    /// whenever they need detectors registered before the first scan.
    public static func bootstrap(
        capabilities: Capabilities = .current,
        quarantineRootURL: URL? = nil,
        userRulesDirectory: URL? = nil
    ) async -> AppEnvironment {
        let environment = AppEnvironment(
            capabilities: capabilities,
            quarantineRootURL: quarantineRootURL,
            userRulesDirectory: userRulesDirectory
        )
        await environment.registerDefaultDetectors()
        return environment
    }

    /// Registers `DevToolsDetectorRegistry.all() + MobileDevDetectorRegistry
    /// .allDetectors() + PowerUserInspectorRegistry.allDetectors()` with
    /// `scanEngine`. Idempotent only in the sense that calling it twice
    /// registers detectors twice (matching `ScanEngine.register`'s own
    /// append-only semantics) — call once per `AppEnvironment` instance,
    /// normally via `bootstrap()`.
    public func registerDefaultDetectors() async {
        await scanEngine.register(DevToolsDetectorRegistry.all())
        await scanEngine.register(MobileDevDetectorRegistry.allDetectors())
        await scanEngine.register(PowerUserInspectorRegistry.allDetectors())
    }

    // MARK: - Scanning

    /// Runs every registered detector, classifies every result through
    /// `safetyClassifier`, and records the outcome in `scanSnapshotStore`
    /// (which both the SwiftUI views and, when running, `RemoteControlServer`
    /// read from). This is the only place in `MainAppUI` that turns raw
    /// `ScanItem`s into `SafetyRules`-classified findings — every view
    /// reuses this snapshot rather than re-classifying on its own.
    @discardableResult
    public func runFullScan(roots: [String] = []) async -> ScanRunResult {
        let startedAt = Date()
        let context = ScanContext(roots: roots)
        let result = await scanEngine.runAll(context: context)
        let findings = result.items.map { item in
            ScanFinding(item: item, verdict: safetyClassifier.classify(item))
        }
        await scanSnapshotStore.record(startedAt: startedAt, finishedAt: Date(), findings: findings)
        return result
    }

    // MARK: - Menu bar

    /// Activates the menu bar status item + popover. Safe to call multiple
    /// times (returns the existing controller after the first call). Must
    /// only be called from a live `NSApplication` session (i.e. from an
    /// app target's `@main App`), never from a test.
    @discardableResult
    public func activateMenuBarAgent(statusBar: NSStatusBar = .system) -> MenuBarController {
        if let menuBarController { return menuBarController }
        let controller = MenuBarController(statusBar: statusBar)
        menuBarController = controller
        return controller
    }

    public func deactivateMenuBarAgent() {
        menuBarController?.removeFromMenuBar()
        menuBarController = nil
    }

    // MARK: - Remote control

    /// Starts the LAN server. Throws / no-ops (returns `nil`) when the
    /// current build flavor doesn't support it — callers (the Remote
    /// Control settings view) should already be hiding this control
    /// entirely per `Capabilities.canRunRemoteControlServer`, but this is
    /// defense in depth against a call site that forgets to check.
    @discardableResult
    public func startRemoteControlServer(port: UInt16 = 8080) throws -> UInt16? {
        guard let remoteControlServer else { return nil }
        return try remoteControlServer.start(port: port)
    }

    public func stopRemoteControlServer() {
        remoteControlServer?.stop()
    }
}
