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
            guard section == .remoteControl else { return true }
            return environment.capabilities.canRunRemoteControlServer
        }
    }

    public var body: some View {
        NavigationSplitView {
            List(visibleSections, selection: $selection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section as SidebarSection?)
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

    @ViewBuilder
    private func detailView(for section: SidebarSection) -> some View {
        switch section {
        case .dashboard:
            DashboardView()
        case .systemJunk:
            SystemJunkPlaceholderView()
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
        case .quarantine:
            QuarantineView()
        case .remoteControl:
            RemoteControlView()
        case .settings:
            SettingsView()
        }
    }
}
