import XCTest
@testable import Optimization

final class AppleScriptLoginItemsQueryTests: XCTestCase {
    /// This only asserts the query degrades gracefully — it never crashes
    /// or throws, regardless of whether `osascript`/System Events
    /// Automation permission is actually available in the environment
    /// running this test (CI sandboxes routinely lack it). A short timeout
    /// keeps this fast even when the permission prompt path would
    /// otherwise stall.
    func testQueryCompletesWithoutThrowingOrCrashing() async {
        let query = AppleScriptLoginItemsQuery(timeout: 2.0)
        let result = await query.queryLoginItemNames()

        // `nil` (unavailable/denied/failed) or a (possibly empty) array of
        // names are both acceptable outcomes; the only real assertion is
        // that this line is ever reached.
        if let result {
            XCTAssertTrue(result.allSatisfy { !$0.isEmpty })
        }
    }
}
