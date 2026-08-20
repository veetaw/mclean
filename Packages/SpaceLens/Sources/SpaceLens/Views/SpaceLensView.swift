import AppKit
import SwiftUI
import UIDesignSystem

/// Space Lens's public entry point: an interactive disk-usage treemap
/// rooted at a starting path (defaults to the whole boot volume, "/" — see
/// ``DirectorySizeTreeBuilder`` and its `MountPointGuard` for how that
/// avoids double-counting the boot volume's separate, firmlinked
/// read-write "Data" volume, and never silently folds in unrelated
/// external/network volumes mounted elsewhere under the tree).
///
/// Owns the only navigation/loading state in this module — a breadcrumb
/// stack of ``DirectoryNode`` from the scan root down to the level
/// currently on screen. Tapping a directory tile drills into that
/// subdirectory's own treemap (its children, laid out fresh in the same
/// view bounds); the breadcrumb bar (or the back button) navigates back up.
/// This is the "interattiva" part of PROMPT MASTER §5.1 — not a static
/// picture.
///
/// The initial scan (and any re-scan triggered by drilling past the
/// original walk's depth limit — see below) runs off the main actor via a
/// detached task (see ``buildTree(root:maxDepth:maxChildrenPerDirectory:maxNodesBudget:)``),
/// with a loading state shown while it's in flight.
///
/// Strictly read-only: the only filesystem side effect anywhere in this
/// view is `NSWorkspace.activateFileViewerSelecting`, which merely asks
/// Finder to reveal a path — nothing in this module deletes, moves, or
/// writes anything.
@available(macOS 26.0, *)
public struct SpaceLensView: View {
    @State private var pathStack: [DirectoryNode]
    @State private var isLoading: Bool
    @State private var errorMessage: String?
    @State private var buildTask: Task<Void, Never>?

    private let rootURL: URL
    private let maxDepth: Int
    private let maxChildrenPerDirectory: Int
    private let maxNodesBudget: Int
    private let skipInitialScan: Bool

    /// - Parameters:
    ///   - rootPath: The directory to start visualizing. Defaults to "/",
    ///     the whole boot volume, when `nil` — `DirectorySizeTreeBuilder`
    ///     is responsible for making that safe (no double-counting the
    ///     firmlinked Data volume, no silently including other mounted
    ///     volumes, graceful handling of SIP-protected paths it can't
    ///     read). A future version could let the user pick a different
    ///     root — e.g. a specific external volume — explicitly instead;
    ///     not built here, out of scope.
    ///   - maxDepth: Forwarded to ``DirectorySizeTreeBuilder``. Drilling
    ///     into a directory that hit this depth limit during the original
    ///     scan transparently triggers a fresh, deeper scan rooted at that
    ///     subdirectory, so this limit bounds each individual scan's cost
    ///     without capping how far a user can actually explore.
    ///   - maxChildrenPerDirectory: Forwarded to ``DirectorySizeTreeBuilder``.
    ///   - maxNodesBudget: Forwarded to ``DirectorySizeTreeBuilder``.
    public init(
        rootPath: String? = nil,
        maxDepth: Int = DirectorySizeTreeBuilder.defaultMaxDepth,
        maxChildrenPerDirectory: Int = DirectorySizeTreeBuilder.defaultMaxChildrenPerDirectory,
        maxNodesBudget: Int = DirectorySizeTreeBuilder.defaultMaxNodesBudget
    ) {
        self.rootURL = rootPath.map { URL(fileURLWithPath: $0) } ?? URL(fileURLWithPath: "/")
        self.maxDepth = maxDepth
        self.maxChildrenPerDirectory = maxChildrenPerDirectory
        self.maxNodesBudget = maxNodesBudget
        self.skipInitialScan = false
        _pathStack = State(initialValue: [])
        _isLoading = State(initialValue: false)
    }

    /// Preview-only entry point that starts directly at an already-built
    /// node instead of walking the real disk, so `#Preview` doesn't have to
    /// scan the canvas machine's actual home directory.
    init(previewRoot: DirectoryNode) {
        self.rootURL = URL(fileURLWithPath: previewRoot.path)
        self.maxDepth = DirectorySizeTreeBuilder.defaultMaxDepth
        self.maxChildrenPerDirectory = DirectorySizeTreeBuilder.defaultMaxChildrenPerDirectory
        self.maxNodesBudget = DirectorySizeTreeBuilder.defaultMaxNodesBudget
        self.skipInitialScan = true
        _pathStack = State(initialValue: [previewRoot])
        _isLoading = State(initialValue: false)
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.3)
            content
        }
        .background(DSColor.background)
        .task { await startInitialScanIfNeeded() }
        .onDisappear { buildTask?.cancel() }
    }

    // MARK: - Header (breadcrumb + controls)

    private var header: some View {
        GlassControlGroup {
            Button("Back", systemImage: "chevron.left") { goBack() }
                .dsButtonStyle(.secondary)
                .disabled(pathStack.count <= 1)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DSSpacing.xxSmall) {
                    ForEach(Array(pathStack.enumerated()), id: \.element.id) { index, node in
                        Button(breadcrumbLabel(for: node)) {
                            pathStack = Array(pathStack.prefix(index + 1))
                        }
                        .dsButtonStyle(index == pathStack.count - 1 ? .primary : .secondary)
                        .controlSize(.small)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            Button("Rescan", systemImage: "arrow.clockwise") { rescanFromRoot() }
                .dsButtonStyle(.secondary)
                .disabled(isLoading)
        }
        .padding(DSSpacing.small)
    }

    private func breadcrumbLabel(for node: DirectoryNode) -> String {
        node.name.isEmpty ? "/" : node.name
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoading && pathStack.isEmpty {
            loadingView(path: rootURL.path)
        } else if let errorMessage {
            errorView(errorMessage)
        } else if let current = pathStack.last {
            if isLoading {
                loadingView(path: current.path)
            } else if current.children.isEmpty {
                emptyLevelView(current)
            } else {
                TreemapLevelView(
                    children: current.childrenBySizeDescending,
                    depth: pathStack.count,
                    onDrillDown: drillDown,
                    onReveal: reveal
                )
                .padding(DSSpacing.small)
            }
        } else {
            loadingView(path: rootURL.path)
        }
    }

    private func loadingView(path: String) -> some View {
        VStack {
            Spacer()
            GlassCard {
                VStack(spacing: DSSpacing.small) {
                    ProgressView()
                    Text("Scanning \(path)…")
                        .font(DSTypography.subheading)
                        .foregroundStyle(DSColor.textSecondary)
                }
                .padding(DSSpacing.small)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack {
            Spacer()
            GlassCard(tint: DSColor.warning.opacity(0.4)) {
                VStack(spacing: DSSpacing.small) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(DSColor.warning)
                    Text(message)
                        .font(DSTypography.subheading)
                        .foregroundStyle(DSColor.textPrimary)
                        .multilineTextAlignment(.center)
                    Button("Retry", systemImage: "arrow.clockwise") { rescanFromRoot() }
                        .dsButtonStyle(.secondary)
                }
                .padding(DSSpacing.small)
                .frame(maxWidth: 320)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // Presentation-only polish (Phase 9 Wave 3, "VisualDesignPass"): adds an
    // icon + a short headline above the existing message so this reads
    // consistently with every other module's empty state, without touching
    // `TreemapLevelView`/`TreemapTileView` or any drill-down/builder logic.
    private func emptyLevelView(_ node: DirectoryNode) -> some View {
        VStack {
            Spacer()
            GlassCard {
                VStack(spacing: DSSpacing.small) {
                    Image(systemName: node.sizeBytes > 0 ? "square.dashed" : "folder")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(DSColor.textTertiary)
                    Text(node.sizeBytes > 0 ? "No Further Breakdown" : "Empty Folder")
                        .font(DSTypography.heading)
                    Text(node.sizeBytes > 0 ? "\(node.name) has no items broken out at this depth." : "\(node.name) is empty.")
                        .font(DSTypography.subheading)
                        .foregroundStyle(DSColor.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(DSSpacing.small)
                .frame(maxWidth: 320)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Navigation

    private func goBack() {
        guard pathStack.count > 1 else { return }
        pathStack.removeLast()
    }

    /// Handles a tap on a treemap tile. Directories with already-materialized
    /// children push directly onto the breadcrumb stack; a directory that
    /// hit the original scan's depth (or global node budget) limit
    /// (non-empty size, no children) triggers a fresh, deeper scan rooted
    /// at that subdirectory instead. A file tile has nothing to drill into,
    /// so it reveals itself in Finder instead — the same read-only action
    /// already offered via the context menu, just also reachable with a
    /// plain click since a dead click on a file tile would otherwise feel
    /// unresponsive. Synthetic aggregate nodes ("N more items") have no
    /// real filesystem path and are not navigable at all.
    private func drillDown(_ node: DirectoryNode) {
        switch node.kind {
        case .directory:
            if !node.children.isEmpty {
                pathStack.append(node)
            } else if node.sizeBytes > 0, let url = node.url {
                rescan(root: url, appending: true)
            }
        case .file:
            reveal(node)
        case .aggregate:
            break
        }
    }

    /// Asks Finder to reveal `node`'s path — read-only (nothing here
    /// selects for deletion or otherwise acts on the file), and the only
    /// filesystem side effect anywhere in this module. This is not a
    /// stepping stone toward a delete action: any future delete/quarantine
    /// capability must go through `MainAppUI`'s existing
    /// `SafetyRules`/`QuarantineConfirmationSheet` pipeline, not something
    /// invented in this read-only package.
    private func reveal(_ node: DirectoryNode) {
        guard let url = node.url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func rescanFromRoot() {
        pathStack = []
        errorMessage = nil
        rescan(root: rootURL, appending: false)
    }

    private func startInitialScanIfNeeded() async {
        guard !skipInitialScan, pathStack.isEmpty, buildTask == nil else { return }
        rescan(root: rootURL, appending: false)
    }

    /// Kicks off a scan and, on success, either replaces the breadcrumb
    /// stack with the new root (`appending: false`) or appends the
    /// freshly-scanned node onto it (`appending: true`, used by
    /// depth-limit-triggered drill-down re-scans).
    ///
    /// This method itself is `@MainActor`-isolated (every `View`'s methods
    /// are, implicitly) and creates a plain, non-detached `Task` — which
    /// therefore also stays on the main actor and may freely read/write
    /// `@State` — but immediately `await`s ``buildTree(root:maxDepth:maxChildrenPerDirectory:maxNodesBudget:)``,
    /// a `nonisolated static` helper that does the actual blocking
    /// filesystem walk on a detached task. That inner detached task's
    /// closure captures only `Sendable` value parameters (`URL`, `Int`) —
    /// never `self` — so it type-checks under strict concurrency while
    /// still keeping the expensive work off the main actor.
    private func rescan(root url: URL, appending: Bool) {
        buildTask?.cancel()
        isLoading = true
        errorMessage = nil
        let maxDepth = maxDepth
        let maxChildrenPerDirectory = maxChildrenPerDirectory
        let maxNodesBudget = maxNodesBudget

        buildTask = Task {
            let built = await Self.buildTree(
                root: url,
                maxDepth: maxDepth,
                maxChildrenPerDirectory: maxChildrenPerDirectory,
                maxNodesBudget: maxNodesBudget
            )
            guard !Task.isCancelled else { return }
            isLoading = false
            guard let built else {
                errorMessage = "Couldn't read \(url.path). It may not exist or may not be readable."
                return
            }
            if appending {
                pathStack.append(built)
            } else {
                pathStack = [built]
            }
        }
    }

    /// Runs `DirectorySizeTreeBuilder.build` on a detached task so the
    /// (potentially slow, real-disk-walking) work never blocks the main
    /// actor. `nonisolated` and `static` so it captures no `View` state —
    /// only the `Sendable` value parameters passed in — which is what lets
    /// `Task.detached`'s closure satisfy strict-concurrency `Sendable`
    /// checking.
    private nonisolated static func buildTree(
        root: URL,
        maxDepth: Int,
        maxChildrenPerDirectory: Int,
        maxNodesBudget: Int
    ) async -> DirectoryNode? {
        await Task.detached(priority: .userInitiated) {
            DirectorySizeTreeBuilder.build(
                root: root,
                maxDepth: maxDepth,
                maxChildrenPerDirectory: maxChildrenPerDirectory,
                maxNodesBudget: maxNodesBudget,
                isCancelled: { Task.isCancelled }
            )
        }.value
    }
}

#if DEBUG
@available(macOS 26.0, *)
#Preview("Space Lens") {
    let leafFile = DirectoryNode(path: "/tmp/preview/notes.txt", name: "notes.txt", kind: .file, sizeBytes: 12_000)
    let cache = DirectoryNode(
        path: "/tmp/preview/Library/Caches",
        name: "Caches",
        kind: .directory,
        sizeBytes: 1_800_000_000,
        children: [
            DirectoryNode(path: "/tmp/preview/Library/Caches/pip", name: "pip", kind: .directory, sizeBytes: 900_000_000),
            DirectoryNode(path: "/tmp/preview/Library/Caches/Homebrew", name: "Homebrew", kind: .directory, sizeBytes: 600_000_000),
            DirectoryNode(path: "/tmp/preview/Library/Caches/misc", name: "misc", kind: .directory, sizeBytes: 300_000_000)
        ]
    )
    let derivedData = DirectoryNode(path: "/tmp/preview/DerivedData", name: "DerivedData", kind: .directory, sizeBytes: 4_300_000_000)
    let movies = DirectoryNode(path: "/tmp/preview/Movies", name: "Movies", kind: .directory, sizeBytes: 2_100_000_000)

    let root = DirectoryNode(
        path: "/tmp/preview",
        name: "preview",
        kind: .directory,
        sizeBytes: cache.sizeBytes + derivedData.sizeBytes + movies.sizeBytes + leafFile.sizeBytes,
        children: [cache, derivedData, movies, leafFile]
    )

    return SpaceLensView(previewRoot: root)
        .frame(width: 820, height: 560)
}
#endif
