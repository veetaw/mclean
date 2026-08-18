import CoreScanEngine
import Foundation

/// Small factory to keep test call sites readable.
enum ScanItemFixture {
    static func make(
        path: String,
        sizeBytes: Int64? = 1024,
        sourceDetectorID: String = "test.fixture",
        category: String = "Test",
        reason: String = "test fixture"
    ) -> ScanItem {
        ScanItem(
            path: path,
            sizeBytes: sizeBytes,
            sourceDetectorID: sourceDetectorID,
            category: category,
            lastUsed: nil,
            reason: reason
        )
    }
}
