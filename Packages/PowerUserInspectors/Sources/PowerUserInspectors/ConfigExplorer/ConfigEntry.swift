import Foundation

/// One entry (file or directory) listed by `ConfigFileExplorer`.
public struct ConfigEntry: Sendable, Hashable, Codable, Identifiable {
    public let id: UUID
    /// Absolute path.
    public let path: String
    /// Last path component.
    public let name: String
    public let isDirectory: Bool
    /// `nil` for directories (the explorer never computes recursive
    /// directory sizes — config directories are typically small, but this
    /// keeps `listEntries` cheap and non-recursive by construction).
    public let sizeBytes: Int64?
    public let modificationDate: Date?
    /// Best-effort syntax guess for editor/highlighting hints, based on
    /// filename/extension only (never file content sniffing).
    public let guessedSyntax: ConfigSyntaxHint

    public init(
        id: UUID = UUID(),
        path: String,
        name: String,
        isDirectory: Bool,
        sizeBytes: Int64?,
        modificationDate: Date?,
        guessedSyntax: ConfigSyntaxHint
    ) {
        self.id = id
        self.path = path
        self.name = name
        self.isDirectory = isDirectory
        self.sizeBytes = sizeBytes
        self.modificationDate = modificationDate
        self.guessedSyntax = guessedSyntax
    }
}

public enum ConfigSyntaxHint: String, Sendable, Codable, CaseIterable {
    case json
    case yaml
    case toml
    case ini
    case plist
    case xml
    case markdown
    case shell
    case sshConfig
    case gitconfig
    case environment
    case plainText
    case unknown
}

/// Filename/extension-based syntax guessing — deliberately shallow (no
/// content sniffing) so it's cheap to run over an entire directory listing.
enum ConfigSyntaxGuesser {
    private static let extensionMap: [String: ConfigSyntaxHint] = [
        "json": .json,
        "yaml": .yaml, "yml": .yaml,
        "toml": .toml,
        "ini": .ini, "cfg": .ini, "conf": .ini,
        "plist": .plist,
        "xml": .xml,
        "md": .markdown, "markdown": .markdown,
        "sh": .shell, "bash": .shell, "zsh": .shell, "fish": .shell,
        "env": .environment
    ]

    /// Filenames (not extensions) with a well-known conventional syntax.
    private static let exactNameMap: [String: ConfigSyntaxHint] = [
        ".zshrc": .shell, ".bashrc": .shell, ".bash_profile": .shell,
        ".zprofile": .shell, ".profile": .shell, ".zshenv": .shell,
        ".gitconfig": .gitconfig, ".gitignore": .plainText,
        "hosts": .plainText, "fstab": .plainText,
        "environment": .environment
    ]

    /// Guesses syntax from a filename alone (no directory context — see
    /// `guess(forPath:)` for entries where the containing directory
    /// disambiguates a generic name like `config`).
    static func guess(forFileName name: String) -> ConfigSyntaxHint {
        if let exact = exactNameMap[name] {
            return exact
        }
        let ext = (name as NSString).pathExtension.lowercased()
        if !ext.isEmpty, let mapped = extensionMap[ext] {
            return mapped
        }
        // Dotfiles with no extension and no exact match (e.g. `.npmrc`,
        // `.curlrc`) are almost always plain key=value or shell-like text,
        // not binary — plainText is a more useful default than unknown.
        if name.hasPrefix(".") {
            return .plainText
        }
        return .unknown
    }

    /// Guesses syntax from a full path, using directory context to
    /// disambiguate a generic filename like `config` (e.g. `~/.ssh/config`
    /// is SSH client config syntax; a bare `config` file elsewhere isn't
    /// assumed to be).
    static func guess(forPath path: String) -> ConfigSyntaxHint {
        if path.hasSuffix("/.ssh/config") {
            return .sshConfig
        }
        return guess(forFileName: (path as NSString).lastPathComponent)
    }
}
