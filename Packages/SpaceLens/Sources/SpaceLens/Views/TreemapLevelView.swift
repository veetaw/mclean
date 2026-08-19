import SwiftUI
import UIDesignSystem

/// Renders one directory's children as a squarified treemap filling the
/// available space, and reports taps (drill-down) and a "reveal in Finder"
/// context-menu action back to its caller.
///
/// Pure presentation: this view holds no navigation state itself —
/// ``SpaceLensView`` owns the breadcrumb stack and decides what happens
/// when a tile is activated. That keeps this view reusable and trivially
/// re-creatable (SwiftUI just lays out a fresh squarified treemap) every
/// time the caller swaps in a different node's children.
@available(macOS 26.0, *)
struct TreemapLevelView: View {
    let children: [DirectoryNode]
    let depth: Int
    let onDrillDown: (DirectoryNode) -> Void
    let onReveal: (DirectoryNode) -> Void

    var body: some View {
        GeometryReader { proxy in
            let rect = CGRect(origin: .zero, size: proxy.size)
            let sizes = children.map { Double($0.sizeBytes) }
            let rects = SquarifiedTreemapLayout.layout(sizes: sizes, in: rect)

            ZStack(alignment: .topLeading) {
                ForEach(children.indices, id: \.self) { index in
                    let node = children[index]
                    TreemapTileView(
                        node: node,
                        siblingIndex: index,
                        depth: depth,
                        rect: rects[index]
                    )
                    .onTapGesture { onDrillDown(node) }
                    .contextMenu {
                        if node.url != nil {
                            Button("Reveal in Finder", systemImage: "folder") {
                                onReveal(node)
                            }
                        }
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
    }
}

#if DEBUG
@available(macOS 26.0, *)
#Preview("Treemap Level") {
    let sample: [DirectoryNode] = [
        DirectoryNode(path: "/tmp/DerivedData", name: "DerivedData", kind: .directory, sizeBytes: 4_300_000_000),
        DirectoryNode(path: "/tmp/Movies", name: "Movies", kind: .directory, sizeBytes: 2_100_000_000),
        DirectoryNode(path: "/tmp/node_modules", name: "node_modules", kind: .directory, sizeBytes: 900_000_000),
        DirectoryNode(path: "/tmp/Photos", name: "Photos Library", kind: .directory, sizeBytes: 640_000_000),
        DirectoryNode(path: "/tmp/big.dmg", name: "installer.dmg", kind: .file, sizeBytes: 210_000_000),
        DirectoryNode(path: "/tmp/notes", name: "notes.txt", kind: .file, sizeBytes: 4_000),
        DirectoryNode(path: "/tmp/.more", name: "38 more items", kind: .aggregate, sizeBytes: 62_000_000)
    ]

    return TreemapLevelView(children: sample, depth: 0, onDrillDown: { _ in }, onReveal: { _ in })
        .padding(DSSpacing.small)
        .background(DSColor.background)
        .frame(width: 720, height: 480)
}
#endif
