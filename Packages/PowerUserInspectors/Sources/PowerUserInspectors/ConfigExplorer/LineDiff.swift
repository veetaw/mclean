import Foundation

/// A minimal, hand-rolled line-based diff — not a full Myers-diff
/// implementation. Config files are typically small (tens to a few hundred
/// lines), so a straightforward O(n·m) LCS dynamic-programming table is
/// plenty fast and easy to verify correct; there's no need to carry a
/// performance-tuned diff engine for what this package uses it for (showing
/// a human "here's what changed" before a config write).
public enum LineDiff {
    public enum ChangeKind: Sendable, Equatable, Codable {
        case unchanged
        case insertion
        case deletion
    }

    public struct Change: Sendable, Equatable, Codable {
        public let kind: ChangeKind
        public let text: String

        public init(kind: ChangeKind, text: String) {
            self.kind = kind
            self.text = text
        }
    }

    /// Line-based diff between `old` and `new`. The result, read in order,
    /// reconstructs `old` from its `.unchanged`/`.deletion` lines and `new`
    /// from its `.unchanged`/`.insertion` lines.
    public static func diff(old: [String], new: [String]) -> [Change] {
        let n = old.count
        let m = new.count
        guard n > 0 || m > 0 else { return [] }

        // dp[i][j] = length of the LCS of old[i...] and new[j...].
        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        if n > 0, m > 0 {
            for i in stride(from: n - 1, through: 0, by: -1) {
                for j in stride(from: m - 1, through: 0, by: -1) {
                    if old[i] == new[j] {
                        dp[i][j] = dp[i + 1][j + 1] + 1
                    } else {
                        dp[i][j] = max(dp[i + 1][j], dp[i][j + 1])
                    }
                }
            }
        }

        var changes: [Change] = []
        var i = 0
        var j = 0
        while i < n, j < m {
            if old[i] == new[j] {
                changes.append(Change(kind: .unchanged, text: old[i]))
                i += 1
                j += 1
            } else if dp[i + 1][j] >= dp[i][j + 1] {
                changes.append(Change(kind: .deletion, text: old[i]))
                i += 1
            } else {
                changes.append(Change(kind: .insertion, text: new[j]))
                j += 1
            }
        }
        while i < n {
            changes.append(Change(kind: .deletion, text: old[i]))
            i += 1
        }
        while j < m {
            changes.append(Change(kind: .insertion, text: new[j]))
            j += 1
        }
        return changes
    }

    /// Convenience overload operating on raw file contents, splitting on
    /// `\n`.
    public static func diff(oldContents: String, newContents: String) -> [Change] {
        diff(old: lines(of: oldContents), new: lines(of: newContents))
    }

    /// Splits `contents` into lines, treating an empty string as **zero**
    /// lines rather than one empty line — `"".components(separatedBy: "\n")`
    /// would otherwise yield `[""]`, which reads as a spurious "removed a
    /// blank line" when diffing against a nonexistent/empty file (e.g.
    /// `ConfigFileExplorer.previewDiff` against a file that doesn't exist
    /// yet).
    private static func lines(of contents: String) -> [String] {
        contents.isEmpty ? [] : contents.components(separatedBy: "\n")
    }
}
