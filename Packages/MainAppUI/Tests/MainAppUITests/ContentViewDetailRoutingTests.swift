import XCTest
@testable import MainAppUI

/// Regression coverage for the "only Dashboard responds" sidebar bug.
///
/// The actual root cause (see `ContentView.body`'s `List` row, the
/// `.tag(section)` comment) was a SwiftUI `List`/`.tag()` generic type
/// mismatch — the sidebar row tagged itself with `SidebarSection?` while
/// `List<SelectionValue, Content>`'s `SelectionValue` was inferred as the
/// non-optional `SidebarSection`, so tapping a row never updated
/// `$selection` at runtime. That failure mode lives entirely inside
/// SwiftUI's opaque, private tag-matching machinery (`List` renders nothing
/// outside a live window, and there is no public API to simulate a click
/// and observe the resulting `selection` binding) — it cannot be exercised
/// by a headless `XCTest` in this package, which is why the real fix relies
/// on the code comment at the fix site rather than a test here.
///
/// What *is* testable without a live AppKit window is `detailView(for:)`'s
/// routing table: every `SidebarSection` case must produce a detail view,
/// and no two sections may resolve to the *same* rendered detail view (the
/// shape of bug this method's own case-exhaustiveness switch — enforced by
/// the compiler, since there is no `default:` case — can't catch: a
/// *present* but copy-pasted-wrong case, e.g. two sections both ending up
/// on `DashboardView()`, which would reproduce the exact same user-visible
/// symptom via a different mechanism than the actual `.tag()` bug). Six
/// sections legitimately *share* `FindingsListView` as a reusable,
/// differently-configured view (System Junk, Developer Tools, Mobile Dev,
/// Power User, Optimization, Privacy) — see `detailIdentity` for how this
/// test still tells those apart.
@available(macOS 26.0, *)
@MainActor
final class ContentViewDetailRoutingTests: XCTestCase {
    private func makeTempDirectory() -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MainAppUITests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeContentView() -> ContentView {
        let environment = AppEnvironment(
            capabilities: .current,
            quarantineRootURL: makeTempDirectory(),
            userRulesDirectory: makeTempDirectory()
        )
        return ContentView(environment: environment, showOnboardingOnFirstLaunch: false)
    }

    /// `detailView(for:)`'s `@ViewBuilder switch` erases every branch to the
    /// *same* static `some View` type -- a fixed tree of SwiftUI's private
    /// `_ConditionalContent<True, False>`, whose generic parameters are
    /// baked in from the switch's shape and identical no matter which case
    /// actually ran. So `type(of:)` on the returned value alone can't tell
    /// two branches apart; every leaf is wrapped in one more
    /// `_ConditionalContent<...>.Storage.trueContent`/`.falseContent`
    /// envelope per switch level. This walks through those envelopes via
    /// `Mirror` (each `_ConditionalContent` exposes its enum `storage`,
    /// which has exactly one child labeled `trueContent`/`falseContent`)
    /// until it reaches a value that isn't itself one of those envelopes --
    /// that's the real leaf view (`DashboardView`, `SettingsView`, ...).
    /// If a future SwiftUI changes `_ConditionalContent`'s private layout,
    /// this simply stops unwrapping and reports whatever level it reached,
    /// so the worst case is a spurious failure here, not a false pass.
    private func leafView(_ value: Any) -> Any {
        let mirror = Mirror(reflecting: value)

        if mirror.displayStyle == .struct, let storage = mirror.children.first(where: { $0.label == "storage" }) {
            return leafView(storage.value)
        }
        if mirror.displayStyle == .enum, let only = mirror.children.first,
           only.label == "trueContent" || only.label == "falseContent" {
            return leafView(only.value)
        }
        return value
    }

    /// A section's "identity": its leaf view's concrete type, plus (for the
    /// six sections that legitimately share `FindingsListView` as a
    /// reusable, differently-configured view -- System Junk, Developer
    /// Tools, Mobile Dev, Power User, Optimization, Privacy) its `title`
    /// stored property, read via `Mirror` since `title` is not otherwise
    /// visible outside the view's own file. Two sections may share a leaf
    /// view *type* by design; they must never share the same fully
    /// resolved identity, since that would mean they render identically.
    private func detailIdentity(_ value: Any) -> String {
        let leaf = leafView(value)
        let typeName = String(reflecting: type(of: leaf))
        let mirror = Mirror(reflecting: leaf)
        if let title = mirror.children.first(where: { $0.label == "title" })?.value as? String {
            return "\(typeName)(title: \(title))"
        }
        return typeName
    }

    /// Every `SidebarSection` case must resolve to a *distinct* detail view
    /// identity (see `detailIdentity`).
    func testEverySidebarSectionRoutesToADistinctDetailView() {
        let contentView = makeContentView()

        var seenIdentities: [String: SidebarSection] = [:]
        for section in SidebarSection.allCases {
            let view = contentView.detailView(for: section)
            let identity = detailIdentity(view)
            if let collidingSection = seenIdentities[identity] {
                XCTFail(
                    "SidebarSection.\(section) and SidebarSection.\(collidingSection) both route to " +
                    "the same detail view (\(identity)) -- detailView(for:) has a copy-paste bug."
                )
            }
            seenIdentities[identity] = section
        }

        XCTAssertEqual(seenIdentities.count, SidebarSection.allCases.count)
    }

    /// `SidebarSection` drives both the sidebar `List` and `detailView(for:)`'s
    /// switch; duplicate ids/titles would make rows visually or structurally
    /// ambiguous even if the routing above is correct.
    func testSidebarSectionCasesHaveUniqueIdentityAndLabels() {
        let allCases = SidebarSection.allCases
        XCTAssertEqual(Set(allCases.map(\.id)).count, allCases.count, "duplicate SidebarSection.id")
        XCTAssertEqual(Set(allCases.map(\.title)).count, allCases.count, "duplicate SidebarSection.title")
    }
}
