import SpaceLens
import SwiftUI
import UIDesignSystem

/// Root view: macOS `NavigationSplitView` sidebar + detail, assembled from
/// `UIDesignSystem` components and every feature package's real backing
/// types via `AppEnvironment`. This is the "Agent:MainAppUI" deliverable —
/// it invents no new detectors/backends of its own, it only wires up what
/// already exists.
@available(macOS 26.0, *)
public struct ContentView: View {
    private let environment: AppEnvironment
    @State private var selection: SidebarSection? = .dashboard
    @State private var showOnboarding: Bool

    public init(environment: AppEnvironment, showOnboardingOnFirstLaunch: Bool = true) {
        self.environment = environment
        self._showOnboarding = State(initialValue: showOnboardingOnFirstLaunch && !OnboardingState.hasCompletedOnboarding())
    }

    private var visibleSections: [SidebarSection] {
        SidebarSection.allCases.filter { section in
            switch section {
            case .remoteControl: environment.capabilities.canRunRemoteControlServer
            case .shredder: environment.capabilities.canRunShredder
            default: true
            }
        }
    }

    public var body: some View {
        NavigationSplitView {
            List(visibleSections, selection: $selection) { section in
                // BUG FIX (only Dashboard ever showed in the detail pane):
                // this row used to tag itself `.tag(section as SidebarSection?)`.
                // `List<SelectionValue, Content>`'s `SelectionValue` generic is
                // inferred as the *non-optional* `SidebarSection` from
                // `$selection`'s `Binding<SidebarSection?>` (the data-driven
                // `List(_:selection:rowContent:)` initializer used here just
                // wraps the base `List(selection: Binding<SelectionValue?>?,
                // content:)` init, so `SelectionValue == SidebarSection`, not
                // `SidebarSection?`). Tagging the row with `SidebarSection?`
                // (i.e. `Optional<SidebarSection>`) made SwiftUI compare tags
                // of a different `Hashable` type than `SelectionValue` — the
                // trait match silently failed on every tap, so `selection`
                // never changed away from its `.dashboard` initial value and
                // `detailView(for:)` kept rendering `DashboardView()` no
                // matter which row was clicked. Tagging with the plain,
                // non-optional `section` matches `SelectionValue` exactly and
                // lets List's built-in tap-to-selection wiring work.
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            VStack(spacing: 0) {
                if environment.capabilities.flavor == .appStore {
                    AppStoreBannerView()
                        .padding([.horizontal, .top], DSSpacing.large)
                }

                detailView(for: selection ?? .dashboard)
            }
        }
        .environment(environment)
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(environment: environment) {
                OnboardingState.markOnboardingCompleted()
                showOnboarding = false
            }
        }
    }

    // `internal` (not `private`) so `MainAppUITests` can call this directly
    // via `@testable import` and assert every `SidebarSection` routes to a
    // distinct, non-crashing detail view — see
    // `ContentViewDetailRoutingTests`. The switch below is already
    // compiler-enforced exhaustive (no `default:` case), which is the real
    // guard against a *missing* case; the test instead guards against a
    // present-but-wrong case (e.g. two sections copy-pasted to the same
    // view), the shape of bug that this method's own exhaustiveness check
    // can't catch.
    @ViewBuilder
    func detailView(for section: SidebarSection) -> some View {
        switch section {
        case .dashboard:
            // `$selection` lets the Dashboard's per-category breakdown rows
            // jump straight to the relevant sidebar section — see
            // `DashboardView`'s doc comment for why this exists (the root
            // cause of "Scan Everything finds GB of data but nothing is
            // clickable").
            DashboardView(selection: $selection)
        case .systemJunk:
            FindingsListView(
                title: "System Junk",
                systemImage: "trash",
                emptyStateMessage: "No trash, large/old files, or duplicates found yet. Rescan to check Finder Trash, Mail/Photos trash, Downloads/Desktop/Documents for large or old files, and exact/similar duplicates.",
                detectorIDs: FeatureDetectorIDs.systemJunk
            )
        case .devTools:
            FindingsListView(
                title: "Developer Tools",
                systemImage: "hammer",
                emptyStateMessage: "No developer toolchain caches found yet. Rescan to check Python, Node, Rust, Go, Ruby, Java, Docker, Xcode, Homebrew, and editor caches.",
                detectorIDs: FeatureDetectorIDs.devTools
            )
        case .mobileDev:
            FindingsListView(
                title: "Mobile Dev",
                systemImage: "iphone.gen3",
                emptyStateMessage: "No mobile toolchain artifacts found yet. Rescan to check Android SDK/AVDs, Simulators, CocoaPods, and Fastlane caches.",
                detectorIDs: FeatureDetectorIDs.mobileDev
            )
        case .powerUser:
            FindingsListView(
                title: "Power User",
                systemImage: "wrench.and.screwdriver",
                emptyStateMessage: "No inventory yet. Rescan to list installed applications.",
                detectorIDs: FeatureDetectorIDs.powerUser
            )
        case .optimization:
            FindingsListView(
                title: "Optimization",
                systemImage: "bolt",
                emptyStateMessage: "No Launch Agents found yet. Rescan to review what runs at login.",
                detectorIDs: FeatureDetectorIDs.optimization
            )
        case .privacy:
            FindingsListView(
                title: "Privacy",
                systemImage: "hand.raised",
                emptyStateMessage: "No browser cache/cookie/history data found yet. Rescan to check Safari, Chrome, and Firefox.",
                detectorIDs: FeatureDetectorIDs.privacy
            )
        case .uninstaller:
            UninstallerView()
        case .maintenance:
            MaintenanceView()
        case .spaceLens:
            SpaceLensView()
        case .quarantine:
            QuarantineView()
        case .shredder:
            ShredderView()
        case .remoteControl:
            RemoteControlView()
        case .settings:
            SettingsView()
        }
    }
}
