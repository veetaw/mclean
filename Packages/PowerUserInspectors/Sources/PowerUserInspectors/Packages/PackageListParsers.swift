import Foundation

/// Pure text/JSON parsers for each package manager's own listing-command
/// output. Kept entirely separate from process-launching (`PackageExplorer`)
/// so they're unit-testable against captured sample CLI output without
/// requiring any of these tools to actually be installed on the machine
/// running the tests.
enum PackageListParsers {
    /// `pip list --format=json` -> `[{"name": "pip", "version": "23.0"}, ...]`
    static func parsePipList(json: String) -> [PackageEntry] {
        guard let data = json.data(using: .utf8) else { return [] }
        struct Row: Decodable { let name: String; let version: String }
        guard let rows = try? JSONDecoder().decode([Row].self, from: data) else { return [] }
        return rows.map { PackageEntry(ecosystem: .pip, name: $0.name, version: $0.version) }
    }

    /// `npm ls -g --depth=0 --json` ->
    /// `{"dependencies": {"npm": {"version": "10.2.0"}, ...}}`
    static func parseNpmGlobalList(json: String) -> [PackageEntry] {
        guard let data = json.data(using: .utf8) else { return [] }
        struct Response: Decodable { let dependencies: [String: Dependency]? }
        struct Dependency: Decodable { let version: String? }
        guard let response = try? JSONDecoder().decode(Response.self, from: data),
              let dependencies = response.dependencies else { return [] }
        return dependencies
            .compactMap { name, dependency -> PackageEntry? in
                guard let version = dependency.version else { return nil }
                return PackageEntry(ecosystem: .npm, name: name, version: version)
            }
            .sorted { $0.name < $1.name }
    }

    /// `cargo install --list` ->
    /// ```
    /// bat v0.24.0:
    ///     bat
    /// cargo-edit v0.12.2:
    ///     cargo-add
    ///     cargo-rm
    /// ripgrep v14.1.0 (https://github.com/BurntSushi/ripgrep):
    ///     rg
    /// ```
    /// Only the un-indented "package vVERSION[:| (source)]" header lines
    /// are packages; indented lines underneath list the binaries each one
    /// installs and are ignored here.
    static func parseCargoInstallList(text: String) -> [PackageEntry] {
        var entries: [PackageEntry] = []
        for line in text.components(separatedBy: "\n") {
            guard !line.hasPrefix(" "), !line.hasPrefix("\t") else { continue }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, let markerRange = trimmed.range(of: " v") else { continue }

            let name = String(trimmed[trimmed.startIndex..<markerRange.lowerBound])
            var versionPart = String(trimmed[markerRange.upperBound...])
            if let colonIndex = versionPart.firstIndex(of: ":") {
                versionPart = String(versionPart[..<colonIndex])
            }
            if let parenIndex = versionPart.firstIndex(of: "(") {
                versionPart = String(versionPart[..<parenIndex])
            }
            let version = versionPart.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !version.isEmpty else { continue }
            entries.append(PackageEntry(ecosystem: .cargo, name: name, version: version))
        }
        return entries
    }

    /// `gem list --local` ->
    /// ```
    /// bigdecimal (default: 3.1.4)
    /// bundler (2.4.10, 2.3.7)
    /// ```
    /// A gem with multiple installed versions produces one `PackageEntry`
    /// per version.
    static func parseGemList(text: String) -> [PackageEntry] {
        var entries: [PackageEntry] = []
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty,
                  let openParen = trimmed.firstIndex(of: "("),
                  trimmed.hasSuffix(")") else { continue }

            let name = trimmed[trimmed.startIndex..<openParen].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }

            let inner = trimmed[trimmed.index(after: openParen)..<trimmed.index(before: trimmed.endIndex)]
            let versions = inner
                .components(separatedBy: ",")
                .map { part -> String in
                    part.replacingOccurrences(of: "default:", with: "").trimmingCharacters(in: .whitespaces)
                }
            for version in versions where !version.isEmpty {
                entries.append(PackageEntry(ecosystem: .gem, name: name, version: version))
            }
        }
        return entries
    }

    /// `go list -m all` (run inside a module directory) -> the first line
    /// is the main module itself (no version); every subsequent line is
    /// `path version` for a dependency.
    static func parseGoListModules(text: String) -> [PackageEntry] {
        var entries: [PackageEntry] = []
        let lines = text.components(separatedBy: "\n")
        for (index, rawLine) in lines.enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let parts = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            if index == 0, parts.count == 1 { continue } // main module: no version to report
            guard parts.count >= 2, parts[1].hasPrefix("v") else { continue }
            entries.append(PackageEntry(ecosystem: .goModules, name: parts[0], version: parts[1]))
        }
        return entries
    }

    /// `brew list --versions` ->
    /// ```
    /// git 2.43.0
    /// node 20.10.0 18.19.0
    /// ```
    /// A formula/cask with multiple installed versions produces one
    /// `PackageEntry` per version.
    static func parseBrewListVersions(text: String) -> [PackageEntry] {
        var entries: [PackageEntry] = []
        for line in text.components(separatedBy: "\n") {
            let parts = line.trimmingCharacters(in: .whitespaces)
                .components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }
            guard parts.count >= 2 else { continue }
            let name = parts[0]
            for version in parts.dropFirst() {
                entries.append(PackageEntry(ecosystem: .homebrew, name: name, version: version))
            }
        }
        return entries
    }
}
