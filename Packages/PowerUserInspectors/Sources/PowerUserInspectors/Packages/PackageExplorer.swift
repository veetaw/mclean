import Foundation

/// Read-only enumeration of installed packages across pip, npm (global),
/// cargo, gem, Go modules (within a given module directory), and Homebrew —
/// each by shelling out to that tool's own list command. This is
/// enumeration only: nothing here ever installs, uninstalls, or updates a
/// package.
///
/// Every `list*` method degrades to `[]` — never throws, never crashes — if
/// the corresponding tool isn't installed, isn't on `PATH`, or its command
/// fails for any reason. A machine with none of these toolchains installed
/// is expected to return `[]` from every method, not an error.
public struct PackageExplorer: Sendable {
    private let commandRunner: ExternalCommandRunning
    private let timeout: TimeInterval

    public init(timeout: TimeInterval = 8) {
        self.commandRunner = RealExternalCommandRunner()
        self.timeout = timeout
    }

    init(commandRunner: ExternalCommandRunning, timeout: TimeInterval = 8) {
        self.commandRunner = commandRunner
        self.timeout = timeout
    }

    // MARK: - pip

    public func listPipPackages() async -> [PackageEntry] {
        for executable in ["pip3", "pip"] {
            guard let result = await commandRunner.run(
                executable: executable,
                arguments: ["list", "--format=json", "--disable-pip-version-check"],
                currentDirectory: nil,
                timeout: timeout
            ) else { continue }
            let entries = PackageListParsers.parsePipList(json: result.standardOutput)
            if !entries.isEmpty { return entries }
        }
        return []
    }

    // MARK: - npm (global)

    public func listNpmGlobalPackages() async -> [PackageEntry] {
        guard let listResult = await commandRunner.run(
            executable: "npm",
            arguments: ["ls", "-g", "--depth=0", "--json"],
            currentDirectory: nil,
            timeout: timeout
        ) else { return [] }

        var entries = PackageListParsers.parseNpmGlobalList(json: listResult.standardOutput)
        guard !entries.isEmpty else { return entries }

        // Best-effort size/last-accessed via npm's own global root — a
        // single extra subprocess call, then plain filesystem reads (no
        // further subprocess calls per package).
        if let rootResult = await commandRunner.run(
            executable: "npm", arguments: ["root", "-g"], currentDirectory: nil, timeout: timeout
        ) {
            let root = rootResult.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            if !root.isEmpty {
                entries = entries.map { enrich($0, installPath: root + "/" + $0.name, recursive: true) }
            }
        }
        return entries
    }

    // MARK: - cargo

    public func listCargoPackages() async -> [PackageEntry] {
        guard let result = await commandRunner.run(
            executable: "cargo", arguments: ["install", "--list"], currentDirectory: nil, timeout: timeout
        ) else { return [] }

        let entries = PackageListParsers.parseCargoInstallList(text: result.standardOutput)
        let cargoBin = NSHomeDirectory() + "/.cargo/bin"
        return entries.map { enrich($0, installPath: cargoBin + "/" + $0.name, recursive: false) }
    }

    // MARK: - gem

    public func listGemPackages() async -> [PackageEntry] {
        guard let result = await commandRunner.run(
            executable: "gem", arguments: ["list", "--local"], currentDirectory: nil, timeout: timeout
        ) else { return [] }
        // No filesystem enrichment: gem's install directory layout varies
        // too much across system Ruby / rbenv / rvm / chruby to guess
        // reliably without an extra `gem environment` call per invocation,
        // which this type deliberately avoids doing per-package.
        return PackageListParsers.parseGemList(text: result.standardOutput)
    }

    // MARK: - Go modules

    /// `go list -m all`, run with `moduleDirectory` as the working
    /// directory (this is inherently scoped to one module's dependency
    /// graph, not a machine-wide "all Go packages" listing — there is no
    /// such thing for `go`).
    public func listGoModules(moduleDirectory: String) async -> [PackageEntry] {
        guard let result = await commandRunner.run(
            executable: "go", arguments: ["list", "-m", "all"], currentDirectory: moduleDirectory, timeout: timeout
        ) else { return [] }
        return PackageListParsers.parseGoListModules(text: result.standardOutput)
    }

    // MARK: - Homebrew

    public func listHomebrewPackages() async -> [PackageEntry] {
        guard let result = await commandRunner.run(
            executable: "brew", arguments: ["list", "--versions"], currentDirectory: nil, timeout: timeout
        ) else { return [] }

        let entries = PackageListParsers.parseBrewListVersions(text: result.standardOutput)
        return entries.map { entry in
            for prefix in ["/opt/homebrew/Cellar", "/usr/local/Cellar"] {
                let candidate = prefix + "/" + entry.name + "/" + entry.version
                if PowerUserFS.exists(candidate) {
                    return enrich(entry, installPath: candidate, recursive: true)
                }
            }
            return entry
        }
    }

    // MARK: - All ecosystems

    /// Runs every listing concurrently. `goModuleDirectory` is optional —
    /// with none given, `.goModules` is simply omitted from the result
    /// (there's no meaningful "all Go modules on this machine" query to
    /// fall back to).
    public func listAll(goModuleDirectory: String? = nil) async -> [PackageEcosystem: [PackageEntry]] {
        async let pip = listPipPackages()
        async let npm = listNpmGlobalPackages()
        async let cargo = listCargoPackages()
        async let gem = listGemPackages()
        async let brew = listHomebrewPackages()

        var result: [PackageEcosystem: [PackageEntry]] = [
            .pip: await pip,
            .npm: await npm,
            .cargo: await cargo,
            .gem: await gem,
            .homebrew: await brew
        ]
        if let goModuleDirectory {
            result[.goModules] = await listGoModules(moduleDirectory: goModuleDirectory)
        }
        return result
    }

    // MARK: - Filesystem enrichment

    private func enrich(_ entry: PackageEntry, installPath: String, recursive: Bool) -> PackageEntry {
        guard PowerUserFS.exists(installPath) else { return entry }
        let size = recursive ? PowerUserFS.recursiveSize(of: installPath) : PowerUserFS.fileSize(installPath)
        return PackageEntry(
            id: entry.id,
            ecosystem: entry.ecosystem,
            name: entry.name,
            version: entry.version,
            sizeBytes: size,
            lastAccessed: PowerUserFS.modificationDate(installPath),
            installPath: installPath
        )
    }
}
