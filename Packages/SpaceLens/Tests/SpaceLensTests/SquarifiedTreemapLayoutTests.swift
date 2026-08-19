import CoreGraphics
import XCTest
@testable import SpaceLens

final class SquarifiedTreemapLayoutTests: XCTestCase {
    private let areaTolerance: Double = 0.5 // absolute sq-pt tolerance for floating rounding
    private let boundsTolerance: CGFloat = 0.01

    // MARK: - Edge cases

    func testEmptyInputReturnsEmptyOutput() {
        let result = SquarifiedTreemapLayout.layout(sizes: [], in: CGRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertTrue(result.isEmpty)
    }

    func testSingleItemGetsTheWholeRect() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 80)
        let result = SquarifiedTreemapLayout.layout(sizes: [42], in: rect)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0], rect)
    }

    func testSingleZeroSizeItemStillGetsTheWholeRect() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 80)
        let result = SquarifiedTreemapLayout.layout(sizes: [0], in: rect)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0], rect)
    }

    func testZeroWidthRectProducesZeroRectsForEveryItem() {
        let rect = CGRect(x: 0, y: 0, width: 0, height: 100)
        let result = SquarifiedTreemapLayout.layout(sizes: [1, 2, 3], in: rect)
        XCTAssertEqual(result, [.zero, .zero, .zero])
    }

    func testZeroHeightRectProducesZeroRectsForEveryItem() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 0)
        let result = SquarifiedTreemapLayout.layout(sizes: [1, 2, 3], in: rect)
        XCTAssertEqual(result, [.zero, .zero, .zero])
    }

    func testAllZeroSizesSplitEvenlyAndStillTileTheRect() {
        let rect = CGRect(x: 10, y: 10, width: 300, height: 60)
        let sizes = [0.0, 0.0, 0.0, 0.0]
        let result = SquarifiedTreemapLayout.layout(sizes: sizes, in: rect)

        XCTAssertEqual(result.count, 4)
        for r in result {
            XCTAssertEqual(r.width, 75, accuracy: 0.001)
            XCTAssertEqual(r.height, 60, accuracy: 0.001)
        }
        assertTiles(result, in: rect)
    }

    func testNegativeSizesAreClampedToZeroAndNeverProduceNaNOrNegativeRects() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 100)
        let sizes = [-50.0, 30.0, -10.0, 20.0]
        let result = SquarifiedTreemapLayout.layout(sizes: sizes, in: rect)

        XCTAssertEqual(result.count, 4)
        for r in result {
            XCTAssertFalse(r.width.isNaN)
            XCTAssertFalse(r.height.isNaN)
            XCTAssertGreaterThanOrEqual(r.width, 0)
            XCTAssertGreaterThanOrEqual(r.height, 0)
        }
        // Negative-size items contribute zero area.
        XCTAssertEqual(result[0].width * result[0].height, 0, accuracy: 0.001)
        XCTAssertEqual(result[2].width * result[2].height, 0, accuracy: 0.001)
        assertTiles(result, in: rect)
    }

    // MARK: - Proportionality (exact area conservation)

    func testEachItemsAreaIsExactlyProportionalToItsSize() {
        let rect = CGRect(x: 0, y: 0, width: 500, height: 300)
        let sizes = [800.0, 400.0, 300.0, 200.0, 100.0, 100.0, 100.0]
        let result = SquarifiedTreemapLayout.layout(sizes: sizes, in: rect)

        let total = sizes.reduce(0, +)
        let rectArea = Double(rect.width) * Double(rect.height)

        for (index, size) in sizes.enumerated() {
            let expectedArea = size / total * rectArea
            let actualArea = Double(result[index].width) * Double(result[index].height)
            XCTAssertEqual(actualArea, expectedArea, accuracy: areaTolerance, "item \(index)")
        }

        assertTiles(result, in: rect)
    }

    func testLargerItemsGetProportionallyLargerAreaOrdering() {
        let rect = CGRect(x: 0, y: 0, width: 400, height: 400)
        let sizes = [100.0, 10.0, 1.0]
        let result = SquarifiedTreemapLayout.layout(sizes: sizes, in: rect)

        let areas = result.map { Double($0.width) * Double($0.height) }
        XCTAssertGreaterThan(areas[0], areas[1])
        XCTAssertGreaterThan(areas[1], areas[2])
    }

    func testTwoEqualSizedItemsSplitTheRectInHalf() {
        let rect = CGRect(x: 0, y: 0, width: 400, height: 100)
        let result = SquarifiedTreemapLayout.layout(sizes: [1, 1], in: rect)

        XCTAssertEqual(result.count, 2)
        let areas = result.map { Double($0.width) * Double($0.height) }
        XCTAssertEqual(areas[0], areas[1], accuracy: 0.01)
        assertTiles(result, in: rect)
    }

    // MARK: - Tiling correctness (no gaps / no overlaps) across varied shapes

    func testTilesExactlyForAFewSimilarlySizedItems() {
        let rect = CGRect(x: 0, y: 0, width: 640, height: 480)
        let sizes = [30.0, 25.0, 20.0, 15.0, 10.0]
        let result = SquarifiedTreemapLayout.layout(sizes: sizes, in: rect)
        assertTiles(result, in: rect)
    }

    func testTilesExactlyForHighlySkewedSizes() {
        let rect = CGRect(x: 0, y: 0, width: 640, height: 480)
        let sizes = [10_000.0, 5.0, 4.0, 3.0, 2.0, 1.0, 1.0, 1.0, 1.0, 1.0]
        let result = SquarifiedTreemapLayout.layout(sizes: sizes, in: rect)
        assertTiles(result, in: rect)
    }

    func testTilesExactlyForManySmallItems() {
        let rect = CGRect(x: 0, y: 0, width: 800, height: 600)
        let sizes = (1...40).map { Double($0) }
        let result = SquarifiedTreemapLayout.layout(sizes: sizes, in: rect)
        assertTiles(result, in: rect)
    }

    func testTilesExactlyForAnExtremelyWideThinTargetRect() {
        let rect = CGRect(x: 0, y: 0, width: 2000, height: 20)
        let sizes = [50.0, 30.0, 15.0, 5.0]
        let result = SquarifiedTreemapLayout.layout(sizes: sizes, in: rect)
        assertTiles(result, in: rect)
    }

    func testTilesExactlyForAnExtremelyTallThinTargetRect() {
        let rect = CGRect(x: 0, y: 0, width: 20, height: 2000)
        let sizes = [50.0, 30.0, 15.0, 5.0]
        let result = SquarifiedTreemapLayout.layout(sizes: sizes, in: rect)
        assertTiles(result, in: rect)
    }

    func testTilesExactlyWithANonZeroOriginRect() {
        // The rect passed in doesn't start at (0,0) — a common case once
        // nested inside a view hierarchy's local coordinate space is offset.
        let rect = CGRect(x: 123, y: 45, width: 500, height: 350)
        let sizes = [7.0, 3.0, 12.0, 1.0, 9.0]
        let result = SquarifiedTreemapLayout.layout(sizes: sizes, in: rect)
        assertTiles(result, in: rect)
    }

    func testTilesExactlyWhenSomeItemsAreZeroSizeAmongPositiveOnes() {
        let rect = CGRect(x: 0, y: 0, width: 500, height: 300)
        let sizes = [40.0, 0.0, 30.0, 0.0, 20.0]
        let result = SquarifiedTreemapLayout.layout(sizes: sizes, in: rect)
        assertTiles(result, in: rect)
        // Zero-size items must not steal area from positive ones.
        XCTAssertEqual(Double(result[1].width) * Double(result[1].height), 0, accuracy: 0.001)
        XCTAssertEqual(Double(result[3].width) * Double(result[3].height), 0, accuracy: 0.001)
    }

    // MARK: - Output ordering matches input ordering

    func testOutputOrderMatchesInputOrderRegardlessOfInternalSortingForTheAlgorithm() {
        let rect = CGRect(x: 0, y: 0, width: 300, height: 300)
        // Deliberately unsorted (ascending) input.
        let sizes = [1.0, 5.0, 3.0, 10.0, 2.0]
        let result = SquarifiedTreemapLayout.layout(sizes: sizes, in: rect)

        XCTAssertEqual(result.count, sizes.count)
        let total = sizes.reduce(0, +)
        let rectArea = Double(rect.width) * Double(rect.height)
        for (index, size) in sizes.enumerated() {
            let expectedArea = size / total * rectArea
            let actualArea = Double(result[index].width) * Double(result[index].height)
            XCTAssertEqual(actualArea, expectedArea, accuracy: areaTolerance, "item at original index \(index)")
        }
    }

    // MARK: - Helpers

    /// Asserts that `rects` exactly tile `target`: every rect lies within
    /// `target`'s bounds, no two rects overlap (beyond a measure-zero
    /// shared edge), and their areas sum to `target`'s full area. Together
    /// these three properties prove a gap-free, overlap-free tiling — any
    /// gap would show up as the area sum falling short of `target`'s area
    /// given that every piece is both disjoint and contained.
    private func assertTiles(_ rects: [CGRect], in target: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        for rect in rects {
            XCTAssertFalse(rect.width.isNaN || rect.height.isNaN, "rect must not be NaN", file: file, line: line)
            XCTAssertGreaterThanOrEqual(rect.width, -boundsTolerance, file: file, line: line)
            XCTAssertGreaterThanOrEqual(rect.height, -boundsTolerance, file: file, line: line)
            XCTAssertGreaterThanOrEqual(rect.minX, target.minX - boundsTolerance, file: file, line: line)
            XCTAssertGreaterThanOrEqual(rect.minY, target.minY - boundsTolerance, file: file, line: line)
            XCTAssertLessThanOrEqual(rect.maxX, target.maxX + boundsTolerance, file: file, line: line)
            XCTAssertLessThanOrEqual(rect.maxY, target.maxY + boundsTolerance, file: file, line: line)
        }

        for i in 0..<rects.count {
            for j in (i + 1)..<rects.count where j > i {
                let overlap = rects[i].intersection(rects[j])
                if overlap.isNull { continue }
                let overlapArea = Double(overlap.width) * Double(overlap.height)
                XCTAssertEqual(overlapArea, 0, accuracy: areaTolerance, "rects \(i) and \(j) must not overlap", file: file, line: line)
            }
        }

        let summedArea = rects.reduce(0.0) { $0 + Double($1.width) * Double($1.height) }
        let targetArea = Double(target.width) * Double(target.height)
        XCTAssertEqual(summedArea, targetArea, accuracy: areaTolerance, "areas must sum to the full target rect (no gaps)", file: file, line: line)
    }
}
