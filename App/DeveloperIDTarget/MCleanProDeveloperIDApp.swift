import MainAppUI
import SwiftUI

/// `@main` entry point for the non-sandboxed, Developer ID target
/// (`MCleanPro-DeveloperID` in `App/project.yml`). All real app assembly
/// lives in `Packages/MainAppUI` — this file only constructs the shared
/// `AppEnvironment` composition root (via the async `bootstrap()` factory,
/// which registers every detector package) and hands it to `ContentView`.
///
/// Compiled *without* `APPSTORE`, so `BuildFlavor.current` resolves to
/// `.developerID` here — see `Capabilities.swift`: the privileged helper,
/// full filesystem scanning, TCC database reads, and the
/// `RemoteControlServer` LAN listener are all available in this flavor.
@main
struct MCleanProDeveloperIDApp: App {
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
                            bootstrapped.activateMenuBarAgent()
                            environment = bootstrapped
                        }
                }
            }
            // Floor for `.windowResizability(.contentSize)` below: keeps the
            // ~220pt sidebar (see ContentView's navigationSplitViewColumnWidth)
            // plus a usable detail pane (FindingsListView rows, SpaceLensView's
            // treemap) from being squeezed below a readable width/height.
            .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1120, height: 760)
        .windowResizability(.contentSize)
    }
}
