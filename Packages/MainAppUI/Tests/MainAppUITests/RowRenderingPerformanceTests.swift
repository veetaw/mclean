import CoreScanEngine
import Dispatch
import Foundation
import UIDesignSystem
import XCTest
@testable import MainAppUI

/// Measures the two concrete, per-row costs identified while auditing
/// `FindingsListView`'s scroll lag: (1) resolving `.app` bundle display
/// name + icon (disk I/O) on every row build, and (2) `ByteCountFormatter`
/// formatting on every row `body` evaluation.
///
/// This intentionally does NOT attempt to benchmark SwiftUI rendering
/// itself — "how long does `List`/`ScrollView` take to scroll N rows" isn't
/// something a plain XCTest can measure, because the dominant fix for the
/// reported lag is structural: `FindingsListView.resultsList` was building
/// every row in a plain `VStack` inside a `ScrollView`, which (unlike
/// `List`/`LazyVStack`) has no virtualization — SwiftUI instantiates and
/// lays out *every* row up front regardless of what's on screen. That's a
/// difference in *how many rows get built at all*, not in the cost of
/// building any single row, so it doesn't show up as a number a
/// microbenchmark can report — it shows up as "SwiftUI does 300 rows' worth
/// of layout work on first appearance instead of ~12." The tests below
/// cover the two costs that *are* per-row and *are* measurable: caching
/// pays off on repeated evaluations of the same row (which happens
/// constantly while scrolling, since SwiftUI recreates row view structs as
/// they cross the visible viewport), independent of the virtualization fix.
final class RowRenderingPerformanceTests: XCTestCase {
    /// Builds `count` `ScanItem`s shaped like a realistic scan snapshot:
    /// mostly cache-directory-style paths, with a real `.app` bundle (with
    /// an actual `Contents/Info.plist` on disk, so `AppBundleDisplayCache`
    /// does real I/O) every 5th item — matching what `InstalledAppsDetector`
    /// actually produces for the Power User section mixed with typical
    /// System Junk-style findings.
    private func makeFixture(count: Int) throws -> (items: [ScanItem], cleanup: () -> Void) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RowRenderingPerfFixture-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        var items: [ScanItem] = []
        for i in 0..<count {
            if i % 5 == 0 {
                let appName = "Fixture App \(i)"
                let bundleURL = root.appendingPathComponent("\(appName).app")
                let contentsURL = bundleURL.appendingPathComponent("Contents")
                try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)
                let plist: [String: Any] = [
                    "CFBundleDisplayName": appName,
                    "CFBundleName": appName,
                    "CFBundleIdentifier": "com.fixture.app\(i)",
                ]
                let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
                try data.write(to: contentsURL.appendingPathComponent("Info.plist"))
                items.append(ScanItem(
                    path: bundleURL.path,
                    sizeBytes: Int64(50_000_000 + i),
                    sourceDetectorID: "poweruser.apps.installed",
                    category: "Installed application",
                    lastUsed: nil,
                    reason: "fixture"
                ))
            } else {
                items.append(ScanItem(
                    path: "/Users/fixture/Library/Caches/pkg-\(i)/cache.db",
                    sizeBytes: Int64(1_000 + i),
                    sourceDetectorID: "dev.python.pip-cache",
                    category: "Python — pip cache",
                    lastUsed: nil,
                    reason: "fixture"
                ))
            }
        }
        return (items, { try? FileManager.default.removeItem(at: root) })
    }

    /// `ScanItemRowDisplay.title(for:)`/`.icon(for:)` are what
    /// `FindingsListView`/`UninstallerView` call per row per `body`
    /// evaluation. This confirms `AppBundleDisplayCache` actually makes
    /// repeated evaluations (i.e. what happens while scrolling, when the
    /// same rows' bodies re-run with no new data) cheap relative to the
    /// first, disk-hitting resolution.
    @MainActor
    func testAppBundleDisplayCacheIsMeasurablyFasterOnRepeatedLookups() throws {
        let (items, cleanup) = try makeFixture(count: 300)
        defer { cleanup() }

        // Cold: first resolution of every item's title/icon — 60 of the 300
        // items are `.app` bundles, each requiring an `Info.plist` read plus
        // an `NSWorkspace.icon(forFile:)` call.
        let coldStart = DispatchTime.now()
        for item in items {
            _ = ScanItemRowDisplay.title(for: item)
            _ = ScanItemRowDisplay.icon(for: item)
        }
        let coldElapsedMs = millis(since: coldStart)

        // Warm x20: the same 300 items resolved again, repeatedly — this is
        // the shape of "the user scrolls the list," where SwiftUI
        // re-evaluates row bodies for items whose underlying data hasn't
        // changed at all.
        let warmStart = DispatchTime.now()
        for _ in 0..<20 {
            for item in items {
                _ = ScanItemRowDisplay.title(for: item)
                _ = ScanItemRowDisplay.icon(for: item)
            }
        }
        let warmPerPassMs = millis(since: warmStart) / 20

        print("""
        [RowRenderingPerformanceTests] 300 items (60 .app bundles):
          cold pass (first resolution, disk I/O):       \(fmt(coldElapsedMs)) ms
          warm pass (cached, avg over 20 re-evaluations): \(fmt(warmPerPassMs)) ms/pass
          speedup: \(fmt(coldElapsedMs / max(warmPerPassMs, 0.001)))x
        """)

        // Sanity guard (not a strict perf gate — CI hardware varies): a
        // fully-cached pass over the same 300 items must be substantially
        // faster than the cold, disk-hitting pass. If this regresses to
        // "about the same," the cache isn't doing its job (e.g. a cache key
        // that isn't actually stable, or a call site bypassing the cache).
        XCTAssertLessThan(warmPerPassMs, coldElapsedMs / 3)
    }

    /// `ScanResultRow.body` calls `Self.formattedSize(sizeBytes)` directly —
    /// i.e. `ByteCountFormatter` runs fresh on every `body` evaluation, not
    /// just once when the item's data was produced. This measures that
    /// per-row cost in isolation so it's a known, bounded quantity rather
    /// than an assumption; it's a real but small cost, made irrelevant by
    /// the `LazyVStack` fix, which limits how many rows are ever evaluated
    /// at once to roughly what's on screen.
    @available(macOS 26.0, *)
    @MainActor
    func testByteCountFormatterCostPerRow() {
        let sizes: [Int64] = (0..<300).map { Int64(1_000 + $0 * 137) }

        let start = DispatchTime.now()
        for _ in 0..<20 {
            for size in sizes {
                _ = ScanResultRow.formattedSize(size)
            }
        }
        let perPassMs = millis(since: start) / 20
        let perRowMicros = (perPassMs * 1000) / Double(sizes.count)

        print("""
        [RowRenderingPerformanceTests] ByteCountFormatter over 300 rows: \
        \(fmt(perPassMs)) ms/pass (~\(fmt(perRowMicros)) µs/row).
        """)

        // Not a hard functional requirement — just documents the magnitude
        // so a future change that makes this dramatically worse (e.g.
        // constructing a new `ByteCountFormatter` per call instead of the
        // static convenience method) shows up as a test failure.
        XCTAssertLessThan(perPassMs, 50)
    }

    private func millis(since start: DispatchTime) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
    }

    private func fmt(_ value: Double) -> String {
        String(format: "%.3f", value)
    }
}
