import CoreScanEngine
import Foundation

/// Resolves the directories this package's detectors should scan.
///
/// Unlike `DevToolsDetectors`/`MobileDevDetectors` (which look for
/// well-known toolchain paths that are cheap to check directly),
/// duplicate/similar-photo finding means recursively hashing/decoding
/// *every* candidate file under the roots — so an unbounded walk of the
/// whole home directory by default would be slow and would surface noisy
/// hits inside places like `~/Library` app support data or source
/// checkouts under `~/Developer`. Default roots are instead the folders
/// where duplicate files and similar photos actually accumulate day to
/// day: `~/Pictures`, `~/Downloads`, `~/Documents`. Any of the three that
/// doesn't exist on this machine is silently skipped.
///
/// When `ScanContext.roots` is non-empty (the common case once the app
/// layer wires up a user-configurable scan scope, and always the case in
/// tests), it is used as-is instead.
enum DuplicateFinderRoots {
    static func resolve(_ context: ScanContext, fileManager: FileManager = .default) -> [String] {
        guard context.roots.isEmpty else { return context.roots }
        let home = fileManager.homeDirectoryForCurrentUser.path
        return [
            home + "/Pictures",
            home + "/Downloads",
            home + "/Documents"
        ].filter { fileManager.fileExists(atPath: $0) }
    }
}
