import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Checks whether a given browser's process is currently running, so
/// detectors can be honest about it in `ScanItem.reason` rather than
/// silently proceeding as if quarantining a live browser's cache/cookie/
/// history files were as safe as quarantining a closed browser's.
///
/// Detectors never *refuse* to list a running browser's files — the user
/// might still want to see and act on them — they only append a prominent
/// warning to the reason text when the check finds a match.
///
/// The lookup is injectable (and `async`, to accommodate `NSWorkspace`
/// access safely regardless of its actor isolation on a given SDK) so tests
/// never depend on what's actually running on the machine executing the
/// test suite.
public struct RunningBrowserCheck: Sendable {
    private let runningBundleIdentifiers: @Sendable () async -> Set<String>

    public init(
        runningBundleIdentifiers: @escaping @Sendable () async -> Set<String> = RunningBrowserCheck.liveRunningBundleIdentifiers
    ) {
        self.runningBundleIdentifiers = runningBundleIdentifiers
    }

    public func isRunning(bundleIdentifier: String) async -> Bool {
        await runningBundleIdentifiers().contains(bundleIdentifier)
    }

    #if canImport(AppKit)
    public static func liveRunningBundleIdentifiers() async -> Set<String> {
        await MainActor.run {
            Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        }
    }
    #else
    public static func liveRunningBundleIdentifiers() async -> Set<String> { [] }
    #endif
}

/// Well-known bundle identifiers for the browsers this package covers.
enum BrowserBundleID {
    static let safari = "com.apple.Safari"
    static let chrome = "com.google.Chrome"
    static let firefox = "org.mozilla.firefox"
}
