import SwiftUI
import UIDesignSystem

/// One rectangle in the treemap: a filled, bordered tile for a single
/// ``DirectoryNode``, with a name/size label when the tile is large enough
/// to hold readable text — tiny tiles render as an unlabeled swatch rather
/// than cramming unreadable text into them.
///
/// Coloring reuses `UIDesignSystem.DSColor.accent` as its single source
/// token (so it adapts to light/dark exactly the way every other token-built
/// surface in this app does) and varies it per sibling/per depth with
/// `.hueRotation` — a categorical spread without inventing a parallel color
/// palette or reaching for the safety-tier tones (`DSColor.safe/.warning/.destructive`),
/// which carry a specific "is this dangerous to delete" meaning elsewhere in
/// this app that would be misleading to reuse for plain disk-usage category
/// color here.
@available(macOS 26.0, *)
struct TreemapTileView: View {
    let node: DirectoryNode
    let siblingIndex: Int
    let depth: Int
    let rect: CGRect

    private var canShowLabel: Bool {
        rect.width >= 44 && rect.height >= 26
    }

    private var canShowSize: Bool {
        rect.width >= 72 && rect.height >= 40
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(DSColor.accent)
                .opacity(fillOpacity)
                .hueRotation(hueAngle)

            Rectangle()
                .strokeBorder(DSColor.separator.opacity(0.7), lineWidth: 1)

            if canShowLabel {
                VStack(alignment: .leading, spacing: 2) {
                    Text(node.name)
                        .font(DSTypography.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if canShowSize {
                        Text(ScanResultRow.formattedSize(node.sizeBytes))
                            .font(DSTypography.caption)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                .padding(6)
                .shadow(color: .black.opacity(0.5), radius: 2)
            }
        }
        .frame(width: max(0, rect.width), height: max(0, rect.height))
        .position(x: rect.midX, y: rect.midY)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(node.name), \(ScanResultRow.formattedSize(node.sizeBytes))"))
    }

    private var fillOpacity: Double {
        switch node.kind {
        case .directory: 0.82
        case .file: 0.50
        case .aggregate: 0.32
        }
    }

    /// Spreads sibling tiles across the color wheel (47° steps stay
    /// visually distinct for a long run before repeating) with a small
    /// per-depth offset so nested levels don't land on the exact same hue
    /// as their parent.
    private var hueAngle: Angle {
        .degrees(Double((siblingIndex * 47 + depth * 23) % 360))
    }
}
