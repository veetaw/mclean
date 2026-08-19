import CoreGraphics

/// A pure, SwiftUI-independent implementation of the "squarified" treemap
/// layout algorithm (Bruls, Huizing & van Wijk, "Squarified Treemaps",
/// 1999) — the standard technique for laying out a treemap so rectangles
/// stay close to square (readable, tappable) instead of degenerating into
/// long thin slivers the way a naive slice-and-dice layout does whenever
/// item sizes are skewed.
///
/// This type has no dependency on SwiftUI or any other UI framework — it is
/// pure geometry over `CGRect`/`Double`, so it can (and is) unit tested
/// directly for tiling correctness, proportionality, and edge cases without
/// a host app or a rendered view hierarchy.
public enum SquarifiedTreemapLayout {

    /// Lays out `sizes` (parallel to the caller's own item array — same
    /// count, same order) within `rect`, returning one `CGRect` per input
    /// item such that the returned rects exactly tile `rect` (no gaps, no
    /// overlaps, modulo floating-point rounding) and each rect's area is
    /// proportional to its item's share of the total size.
    ///
    /// Edge cases:
    /// - `sizes.isEmpty` → `[]`.
    /// - `sizes.count == 1` → `[rect]` (the single item gets the whole
    ///   rect; no algorithm needed).
    /// - `rect` has zero width or height → every item gets a zero rect
    ///   (nothing to lay out into).
    /// - Every size is zero (or `sizes` contains only non-positive values)
    ///   → the rect is split evenly (slice-and-dice along its longer axis)
    ///   so every item still gets a visible slice, since there is no size
    ///   signal to size them proportionally by.
    /// - Negative sizes are clamped to zero rather than trusted — this
    ///   function never produces a negative-area or NaN rect.
    public static func layout(sizes: [Double], in rect: CGRect) -> [CGRect] {
        guard !sizes.isEmpty else { return [] }
        guard rect.width > 0, rect.height > 0 else {
            return Array(repeating: .zero, count: sizes.count)
        }
        guard sizes.count > 1 else {
            return [rect]
        }

        let clamped = sizes.map { max(0, $0) }
        let total = clamped.reduce(0, +)
        guard total > 0 else {
            return equalSplit(count: clamped.count, in: rect)
        }

        // The squarify algorithm's worst-ratio heuristic assumes rows are
        // built by walking items largest-first, so sort once up front and
        // map results back to the caller's original order at the end.
        let order = clamped.indices.sorted { clamped[$0] > clamped[$1] }

        // Scale sizes into areas that sum to exactly the rect's area, so
        // the algorithm works regardless of the caller's units (bytes,
        // item counts, ...) — it only ever reasons in area terms.
        let rectArea = Double(rect.width) * Double(rect.height)
        let scale = rectArea / total
        let sortedAreas = order.map { clamped[$0] * scale }

        let sortedRects = squarify(areas: sortedAreas, rect: rect)

        var result = [CGRect](repeating: .zero, count: clamped.count)
        for (sortedIndex, originalIndex) in order.enumerated() {
            result[originalIndex] = sortedRects[sortedIndex]
        }
        return result
    }

    // MARK: - Equal split (all-zero-size fallback)

    private static func equalSplit(count: Int, in rect: CGRect) -> [CGRect] {
        guard count > 0 else { return [] }
        if rect.width >= rect.height {
            let w = rect.width / CGFloat(count)
            return (0..<count).map {
                CGRect(x: rect.minX + CGFloat($0) * w, y: rect.minY, width: w, height: rect.height)
            }
        } else {
            let h = rect.height / CGFloat(count)
            return (0..<count).map {
                CGRect(x: rect.minX, y: rect.minY + CGFloat($0) * h, width: rect.width, height: h)
            }
        }
    }

    // MARK: - Core squarify algorithm

    /// `areas` must be sorted descending and (approximately) sum to
    /// `rect.width * rect.height`. Returns one rect per area, same order.
    private static func squarify(areas: [Double], rect: CGRect) -> [CGRect] {
        var results = [CGRect](repeating: .zero, count: areas.count)
        var remaining = rect
        var row: [Int] = []
        var i = 0

        while i < areas.count || !row.isEmpty {
            let side = Double(min(remaining.width, remaining.height))

            if i < areas.count {
                let candidateRow = row + [i]
                let currentWorst = worstRatio(areas: row.map { areas[$0] }, sideLength: side)
                let candidateWorst = worstRatio(areas: candidateRow.map { areas[$0] }, sideLength: side)

                if row.isEmpty || candidateWorst <= currentWorst {
                    row.append(i)
                    i += 1
                    continue
                }
            }

            remaining = layoutRow(row, areas: areas, rect: remaining, results: &results)
            row = []
        }

        return results
    }

    /// The paper's "worst aspect ratio" for a candidate row: the largest
    /// deviation from square that any single item in the row would have if
    /// the row were laid out into a strip of the given `sideLength` right
    /// now. Lower is better (closer to square); `1.0` is a perfect square.
    private static func worstRatio(areas: [Double], sideLength: Double) -> Double {
        guard sideLength > 0, let rowMax = areas.max(), let rowMin = areas.min(), rowMin > 0 else {
            return .infinity
        }
        let sum = areas.reduce(0, +)
        guard sum > 0 else { return .infinity }
        let sideSquared = sideLength * sideLength
        let a = (sideSquared * rowMax) / (sum * sum)
        let b = (sum * sum) / (sideSquared * rowMin)
        return max(a, b)
    }

    /// Commits `row` (indices into `areas`) as a strip along the shorter
    /// side of `rect`, writes each item's rect into `results`, and returns
    /// the rect that remains after removing that strip.
    private static func layoutRow(
        _ row: [Int],
        areas: [Double],
        rect: CGRect,
        results: inout [CGRect]
    ) -> CGRect {
        guard !row.isEmpty else { return rect }

        let rowAreas = row.map { areas[$0] }
        let rowTotal = rowAreas.reduce(0, +)
        let width = Double(rect.width)
        let height = Double(rect.height)

        guard rowTotal > 0, width > 0, height > 0 else {
            for index in row { results[index] = .zero }
            return rect
        }

        let x0 = Double(rect.minX)
        let y0 = Double(rect.minY)

        if width >= height {
            // Wider-than-tall remainder: cut a vertical strip on the left
            // spanning the full height; stack row items top-to-bottom
            // within it.
            let stripWidth = rowTotal / height
            var y = y0
            for (offset, index) in row.enumerated() {
                let isLast = offset == row.count - 1
                let itemHeight = isLast ? (y0 + height) - y : rowAreas[offset] / stripWidth
                results[index] = CGRect(x: x0, y: y, width: stripWidth, height: itemHeight)
                y += itemHeight
            }
            return CGRect(x: x0 + stripWidth, y: y0, width: width - stripWidth, height: height)
        } else {
            // Taller-than-wide remainder: cut a horizontal strip on top
            // spanning the full width; lay row items left-to-right within
            // it.
            let stripHeight = rowTotal / width
            var x = x0
            for (offset, index) in row.enumerated() {
                let isLast = offset == row.count - 1
                let itemWidth = isLast ? (x0 + width) - x : rowAreas[offset] / stripHeight
                results[index] = CGRect(x: x, y: y0, width: itemWidth, height: stripHeight)
                x += itemWidth
            }
            return CGRect(x: x0, y: y0 + stripHeight, width: width, height: height - stripHeight)
        }
    }
}
