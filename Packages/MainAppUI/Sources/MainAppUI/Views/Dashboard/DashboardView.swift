import CoreScanEngine
import RemoteControlServer
import SwiftUI
import UIDesignSystem

/// Landing screen: aggregate figures across every registered detector,
/// pulled from the same `AppEnvironment.scanSnapshotStore` snapshot every
/// other section reads — the Dashboard never runs its own separate scan
/// logic.
///
/// ROOT CAUSE FIX ("Scan Everything finds GB of data but nothing is
/// clickable"): before this fix, this view only rendered three read-only
/// stat cards (counts/bytes as plain `Text`) after running a scan — there
/// was no button, link, or navigation of any kind from here to the actual
/// findings, which only ever lived in the per-category sidebar sections
/// (System Junk, Developer Tools, …), each backed by its own
/// `FindingsListView`. A user who ran "Scan Everything" from the Dashboard
/// (the obvious, most-discoverable entry point) saw a big reclaimable
/// number and zero clickable affordances anywhere on screen; they'd have to
/// already know to manually visit unrelated sidebar tabs to find a
/// clickable "Quarantine" button. That's not a binding bug or a disabled
/// button — `FindingsListView`'s row actions and `QuarantineConfirmationSheet`
/// wiring are correct (verified by reading them) and reachable *once you're
/// on the right tab*; the Dashboard itself was simply a dead end. The fix:
/// group the shared snapshot's findings by the same `FeatureDetectorIDs`
/// sets `ContentView` uses to route sidebar sections, and render each
/// non-empty category as a tappable row that sets the sidebar `selection`
/// binding — turning the Dashboard's summary into an actual index into the
/// clickable findings, using navigation infrastructure that already exists.
@available(macOS 26.0, *)
struct DashboardView: View {
    @Environment(AppEnvironment.self) private var environment
    /// Bound to `ContentView`'s sidebar selection so a tapped category row
    /// can navigate there directly, instead of leaving the user to find the
    /// right sidebar entry on their own.
    @Binding var selection: SidebarSection?

    @State private var findings: [ScanFinding] = []
    @State private var quarantineCount = 0
    @State private var lastScanFinishedAt: Date?

    // Deliberately NOT local `@State` — see `ScanRunner`'s doc comment and
    // `FindingsListView`'s matching comment. Reading straight from
    // `AppEnvironment.scanRunner` means a scan started from *this* view or
    // any `FindingsListView` section is visible here (spinner + progress)
    // without the Dashboard needing to have been the one that triggered it,
    // and without resetting when `ContentView`'s sidebar switch recreates
    // this view on navigation.
    private var isScanning: Bool { environment.scanRunner.isScanning }

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    private var findingsCount: Int { findings.count }
    private var totalReclaimableBytes: Int64 {
        findings.reduce(Int64(0)) { $0 + ($1.item.sizeBytes ?? 0) }
    }

    /// Per-sidebar-section rollup of the current snapshot, category order
    /// matching the sidebar's own order. Only non-empty categories are
    /// shown — an empty list here (with a scan already run) means the scan
    /// genuinely found nothing outside what the stat cards already show.
    private var categoryBreakdown: [CategoryBreakdown] {
        Self.categories.compactMap { category in
            let matches = findings.filter { category.detectorIDs.contains($0.item.sourceDetectorID) }
            guard !matches.isEmpty else { return nil }
            let bytes = matches.reduce(Int64(0)) { $0 + ($1.item.sizeBytes ?? 0) }
            return CategoryBreakdown(
                section: category.section,
                title: category.title,
                systemImage: category.systemImage,
                count: matches.count,
                reclaimableBytes: bytes
            )
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.large) {
                // The Dashboard's "hero": one glass surface carrying the
                // app title, the live scan status line (folded in from what
                // used to be a separate "Last Scan" card below — same
                // `lastScanSummary` string, just no longer duplicated), and
                // the single primary CTA ("Scan Everything"). This is the
                // "big status hero, one clear primary action" layout this
                // phase's brief asks for — no new colors, still
                // `DSColor.accent`/`GlassCard`.
                GlassCard(tint: DSColor.accent.opacity(0.12)) {
                    VStack(alignment: .leading, spacing: DSSpacing.medium) {
                        HStack(alignment: .top, spacing: DSSpacing.medium) {
                            ModuleIconBadge(systemImage: "sparkle.magnifyingglass", tint: DSColor.accent, size: 56)
                            VStack(alignment: .leading, spacing: DSSpacing.xxSmall) {
                                Text("MClean Pro")
                                    .font(DSTypography.largeTitle)
                                Text(lastScanSummary)
                                    .font(DSTypography.subheading)
                                    .foregroundStyle(DSColor.textSecondary)
                            }
                            Spacer(minLength: DSSpacing.small)
                        }

                        // "Scan Everything" is the ONLY thing that triggers a
                        // full rescan on this screen — `.task { await
                        // refresh() }` below only ever reads the existing
                        // cached snapshot on appear, it never scans
                        // automatically. That's deliberate: the Dashboard's
                        // stat cards should show cached, already-fresh
                        // results instantly, and only re-scan when the user
                        // explicitly asks for one.
                        GlassControlGroup {
                            Button("Scan Everything", systemImage: "sparkle.magnifyingglass") {
                                Task { await scanNow() }
                            }
                            .dsButtonStyle(.primary)
                            .disabled(isScanning)

                            if isScanning {
                                ProgressView(value: environment.scanRunner.progress)
                                    .controlSize(.small)
                                    .frame(width: 100)
                                    .padding(.leading, DSSpacing.xSmall)
                                // Completion-count-based ("N of M detectors
                                // done"), not time-based — see
                                // `ScanRunner.progress`.
                                Text("\(Int(environment.scanRunner.progress * 100))%")
                                    .font(DSTypography.subheading)
                                    .foregroundStyle(DSColor.textSecondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if isScanning && !environment.scanRunner.categoryProgress.isEmpty {
                    scanProgressBreakdown
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: DSSpacing.medium)], spacing: DSSpacing.medium) {
                    statCard(title: "Findings", value: "\(findingsCount)", systemImage: "magnifyingglass", tint: DSColor.accent)
                    statCard(title: "Reclaimable", value: ScanResultRow.formattedSize(totalReclaimableBytes), systemImage: "internaldrive", tint: DSColor.safe)
                    statCard(title: "In Quarantine", value: "\(quarantineCount)", systemImage: "xmark.bin", tint: DSColor.warning)
                }

                if !categoryBreakdown.isEmpty {
                    VStack(alignment: .leading, spacing: DSSpacing.small) {
                        Text("Review Findings").font(DSTypography.heading)
                        GlassCard(padding: 0) {
                            VStack(spacing: 0) {
                                ForEach(categoryBreakdown) { category in
                                    Button {
                                        // Navigates to the sidebar section
                                        // whose `FindingsListView` already
                                        // has the working per-row
                                        // "Quarantine" action + confirmation
                                        // sheet — this is the actual "make
                                        // it clickable" fix.
                                        selection = category.section
                                    } label: {
                                        categoryRow(category)
                                    }
                                    .buttonStyle(.plain)

                                    if category.id != categoryBreakdown.last?.id {
                                        Divider().opacity(0.3)
                                    }
                                }
                            }
                        }
                    }
                } else if lastScanFinishedAt != nil {
                    ModuleEmptyStateCard(
                        systemImage: "checkmark.seal",
                        headline: "Nothing to Clean",
                        message: "No cleanable items found in the last scan. Your Mac looks tidy.",
                        tint: DSColor.safe
                    )
                }

                Text("Build flavor: \(environment.capabilities.flavor.rawValue)")
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColor.textTertiary)
            }
            .padding(DSSpacing.xLarge)
        }
        // Reads the existing cached snapshot only — never triggers a scan.
        // "Scan Everything" (above) is the sole explicit rescan trigger.
        .task { await refresh() }
        // Keeps the stat cards live if a scan started/finished from
        // elsewhere (another `FindingsListView` section, or this same
        // button) while this view is visible — see the matching comment in
        // `FindingsListView`.
        .onChange(of: environment.scanRunner.isScanning) { _, nowScanning in
            if !nowScanning {
                Task { await refresh() }
            }
        }
    }

    /// "Last scanned: 3 minutes ago" (relative, per the product ask),
    /// falling back to an explicit "never scanned" message rather than an
    /// empty/blank state.
    private var lastScanSummary: String {
        guard let lastScanFinishedAt else {
            return "Never scanned — tap Scan Everything to check your Mac."
        }
        let relative = Self.relativeDateFormatter.localizedString(for: lastScanFinishedAt, relativeTo: Date())
        return "Last scanned \(relative)"
    }

    /// Per-`DetectorCategory` "N/M detectors complete" rows, shown only
    /// while a scan is in progress. This is a coarser grouping than the
    /// sidebar's own sections (e.g. "System Junk" spans several
    /// `DetectorCategory` values — trash, largeAndOldFiles, duplicates,
    /// systemJunk), so it's presented here as its own "by scan module"
    /// breakdown rather than folded into `categoryBreakdown` above.
    private var scanProgressBreakdown: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: DSSpacing.xSmall) {
                Text("Scanning by module").font(DSTypography.subheading).foregroundStyle(DSColor.textSecondary)
                ForEach(sortedCategoryProgress, id: \.category) { entry in
                    HStack {
                        Text(entry.category.displayName)
                            .font(DSTypography.caption)
                            .foregroundStyle(DSColor.textPrimary)
                        Spacer()
                        Text("\(entry.progress.completed)/\(entry.progress.total)")
                            .font(DSTypography.caption)
                            .foregroundStyle(DSColor.textSecondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var sortedCategoryProgress: [(category: DetectorCategory, progress: ScanRunner.CategoryProgress)] {
        environment.scanRunner.categoryProgress
            .map { (category: $0.key, progress: $0.value) }
            .sorted { $0.category.displayName < $1.category.displayName }
    }

    private func statCard(title: String, value: String, systemImage: String, tint: Color) -> some View {
        GlassCard(tint: tint.opacity(0.18)) {
            VStack(alignment: .leading, spacing: DSSpacing.xSmall) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(tint)
                Text(value)
                    .font(DSTypography.title)
                Text(title)
                    .font(DSTypography.subheading)
                    .foregroundStyle(DSColor.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func categoryRow(_ category: CategoryBreakdown) -> some View {
        HStack(spacing: DSSpacing.medium) {
            Image(systemName: category.systemImage)
                .font(.title3)
                .foregroundStyle(DSColor.textSecondary)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: DSSpacing.xxSmall) {
                Text(category.title)
                    .font(DSTypography.heading)
                    .foregroundStyle(DSColor.textPrimary)
                Text("\(category.count) item\(category.count == 1 ? "" : "s") · \(ScanResultRow.formattedSize(category.reclaimableBytes)) reclaimable")
                    .font(DSTypography.subheading)
                    .foregroundStyle(DSColor.textSecondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(DSColor.textTertiary)
        }
        .padding(.vertical, DSSpacing.small)
        .padding(.horizontal, DSSpacing.medium)
        // Makes the whole row hit-testable as a click target, not just the
        // text/icon glyphs themselves (an `HStack` with a `Spacer` only
        // hit-tests its non-transparent children by default).
        .contentShape(Rectangle())
    }

    private func refresh() async {
        let snapshot = await environment.scanSnapshotStore.currentSnapshot()
        findings = snapshot.findings
        lastScanFinishedAt = snapshot.lastScanFinishedAt
        quarantineCount = (try? await environment.quarantineManager.listActive().count) ?? 0
    }

    private func scanNow() async {
        // `environment.runFullScan()` drives `environment.scanRunner`'s
        // `isScanning`/`progress` for the duration and guards against a
        // duplicate concurrent scan — nothing to track locally here.
        await environment.runFullScan()
        await refresh()
    }

    // MARK: - Category breakdown model

    private struct CategoryBreakdown: Identifiable {
        let section: SidebarSection
        let title: String
        let systemImage: String
        let count: Int
        let reclaimableBytes: Int64
        var id: SidebarSection { section }
    }

    /// Mirrors `ContentView.detailView(for:)`'s `FindingsListView` sections
    /// and the `FeatureDetectorIDs` each one filters by, so the Dashboard's
    /// breakdown never lists a category that isn't actually a clickable
    /// sidebar destination.
    private static let categories: [(section: SidebarSection, title: String, systemImage: String, detectorIDs: Set<String>)] = [
        (.systemJunk, "System Junk", "trash", FeatureDetectorIDs.systemJunk),
        (.devTools, "Developer Tools", "hammer", FeatureDetectorIDs.devTools),
        (.mobileDev, "Mobile Dev", "iphone.gen3", FeatureDetectorIDs.mobileDev),
        (.powerUser, "Power User", "wrench.and.screwdriver", FeatureDetectorIDs.powerUser),
        (.optimization, "Optimization", "bolt", FeatureDetectorIDs.optimization),
        (.privacy, "Privacy", "hand.raised", FeatureDetectorIDs.privacy),
    ]
}
