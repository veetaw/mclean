import Foundation

/// Minimal glob matcher for `SafetyRule.Match.pathGlob`. Deliberately not
/// built on `fnmatch(3)`: without `FNM_PATHNAME`, libc's `*` already
/// crosses `/` boundaries (behaving like `**`), which would make a single
/// `*` in a rule file silently far broader than a rule author would
/// expect — this implementation gives `*` and `**` their conventional,
/// distinct meanings instead:
///
/// - `**` matches any run of characters, including `/` (any depth).
/// - `*` matches any run of characters *except* `/` (one path component).
/// - `?` matches exactly one character except `/`.
/// - Everything else is matched literally.
public enum GlobMatcher {
    public static func matches(pattern: String, path: String) -> Bool {
        let regexPattern = "^" + translate(pattern) + "$"
        guard let regex = try? NSRegularExpression(pattern: regexPattern) else { return false }
        let range = NSRange(path.startIndex..., in: path)
        return regex.firstMatch(in: path, range: range) != nil
    }

    private static func translate(_ pattern: String) -> String {
        var result = ""
        let chars = Array(pattern)
        var index = 0
        while index < chars.count {
            let char = chars[index]
            if char == "*" {
                if index + 1 < chars.count, chars[index + 1] == "*" {
                    result += ".*"
                    index += 2
                    continue
                }
                result += "[^/]*"
            } else if char == "?" {
                result += "[^/]"
            } else if "\\^$.|+()[]{}".contains(char) {
                result += "\\\(char)"
            } else {
                result.append(char)
            }
            index += 1
        }
        return result
    }
}
