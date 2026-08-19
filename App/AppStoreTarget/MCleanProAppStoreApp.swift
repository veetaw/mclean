import MainAppUI
import SwiftUI

/// `@main` entry point for the sandboxed, Mac App Store target
/// (`MCleanPro-AppStore` in `App/project.yml`). All real app assembly
/// lives in `Packages/MainAppUI` — this file only constructs the shared
/// `AppEnvironment` composition root (via the async `bootstrap()` factory,
/// which registers every detector package) and hands it to `ContentView`.
///
/// Compiled with `SWIFT_ACTIVE_COMPILATION_CONDITIONS: APPSTORE`, so
/// `BuildFlavor.current` (and therefore every `Capabilities` flag) resolves
/// to `.appStore` here — see `Capabilities.swift` for what that disables.
@main
struct MCleanProAppStoreApp: App {
    @State private var environment: AppEnvironment?

    var body: some Scene {
        WindowGroup {
            Group {
                if let environment {
                    ContentView(environment: environment)
                } else {
                    ProgressView("Starting MClean Pro…")
                        .frame(minWidth: 480, minHeight: 320)
                        .task {
                            let bootstrapped = await AppEnvironment.bootstrap()
                            // Sandbox-legal: a status item + scheduled scan
                            // of the sandbox container. See
                            // `Capabilities.canRunMenuBarAgent` (true in
                            // both flavors) and `AppEnvironment
                            // .activateMenuBarAgent()`'s doc comment for
                            // why this is a separate, explicit step.
                            bootstrapped.activateMenuBarAgent()
                            environment = bootstrapped
                        }
                }
            }
            // Floor for `.windowResizability(.contentSize)` below: keeps the
            // ~220pt sidebar (see ContentView's navigationSplitViewColumnWidth)
            // plus a usable detail pane (FindingsListView rows, SpaceLensView's
            // treemap) from being squeezed below a readable width/height.
            // Kept consistent with the DeveloperID target's window sizing.
            .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1120, height: 760)
        .windowResizability(.contentSize)
    }
}
