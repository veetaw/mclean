import Foundation
import CoreScanEngine

/// Resolves the directories a detector should treat as "home" roots from
/// `ScanContext`.
///
/// Falls back to the real user home directory when the context doesn't
/// specify any (the common case in production, where the app layer builds a
/// `ScanContext` with default roots). Tests pass one or more sandboxed temp
/// directories via `ScanContext.roots` so detector logic can be exercised in
/// isolation from whatever happens to exist on the machine running the test.
///
/// Mirrors `DevToolsDetectors.HomeDirectories` / `TrashCleaner.HomeDirectories`
/// — duplicated here rather than shared because `PrivacyCleaner` deliberately
/// depends only on `CoreScanEngine`, matching every other detector package in
/// this repo.
enum HomeDirectories {
    static func resolve(_ context: ScanContext) -> [String] {
        context.roots.isEmpty ? [NSHomeDirectory()] : context.roots
    }
}
