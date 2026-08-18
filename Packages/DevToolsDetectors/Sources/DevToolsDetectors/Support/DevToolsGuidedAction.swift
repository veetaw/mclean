import Foundation

/// A suggested maintenance command surfaced to the user rather than executed.
///
/// Some toolchain maintenance (notably `brew cleanup` / `brew autoremove`,
/// see `HomebrewDetector`) doesn't reduce to "move this path to quarantine"
/// — it mutates a package manager's own bookkeeping of installed
/// dependencies, which only that tool can safely do. Detectors stay
/// strictly read-only and never invoke these commands themselves; a
/// `DevToolsGuidedAction` is purely descriptive data for the UI to present,
/// with the user deciding whether to run the command in their own shell.
public struct DevToolsGuidedAction: Sendable, Hashable, Codable, Identifiable {
    public let id: String
    public let title: String
    public let command: String
    public let explanation: String

    public init(id: String, title: String, command: String, explanation: String) {
        self.id = id
        self.title = title
        self.command = command
        self.explanation = explanation
    }
}
