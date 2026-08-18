import Foundation
import CoreScanEngine

/// Finds Python toolchain caches and orphaned artifacts:
/// - `pip`'s download/wheel cache
/// - conda/mamba's extracted package cache
/// - virtualenvs that look orphaned (their owning project no longer exists,
///   or — best-effort — no linked project record can be found at all)
/// - stray `__pycache__` bytecode directories
/// - Jupyter's cache/data directories
///
/// Strictly read-only: only reads paths and metadata, never deletes or moves
/// anything. See `CoreScanEngine.Detector`.
public struct PythonDetector: Detector {
    public let id = "dev.python"
    public let displayName = "Python"
    public let category: DetectorCategory = .devTools

    /// How long a virtualenv (with no `.project` marker to check against)
    /// must sit untouched before it's flagged as a possible orphan.
    private let staleVirtualenvThreshold: TimeInterval
    private let now: @Sendable () -> Date

    public init(
        staleVirtualenvThreshold: TimeInterval = 180 * 24 * 3600,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.staleVirtualenvThreshold = staleVirtualenvThreshold
        self.now = now
    }

    public func scan(context: ScanContext) async throws -> [ScanItem] {
        var items: [ScanItem] = []
        for home in HomeDirectories.resolve(context) {
            if Task.isCancelled { break }
            items.append(contentsOf: scanPipCache(home: home))
            items.append(contentsOf: scanCondaCaches(home: home))
            items.append(contentsOf: scanVirtualenvContainers(home: home))
            items.append(contentsOf: scanJupyterCache(home: home))
            if Task.isCancelled { break }
            items.append(contentsOf: scanStrayPycache(home: home))
        }
        return items
    }

    // MARK: - pip

    private func scanPipCache(home: String) -> [ScanItem] {
        let path = home + "/Library/Caches/pip"
        guard DevToolsFS.isDirectory(path) else { return [] }
        return [ScanItem(
            path: path,
            sizeBytes: DevToolsFS.recursiveSize(of: path, isCancelled: { Task.isCancelled }),
            sourceDetectorID: "dev.python.pip-cache",
            category: "Python — pip cache",
            lastUsed: DevToolsFS.modificationDate(path).map { LastUsedEvidence(date: $0, source: .filesystemMTime) },
            reason: "pip's download/wheel cache. pip re-downloads and re-builds wheels as needed on the next install; safe to clear."
        )]
    }

    // MARK: - conda / mamba

    private func scanCondaCaches(home: String) -> [ScanItem] {
        let candidates = [
            home + "/.conda/pkgs",
            home + "/miniconda3/pkgs",
            home + "/miniforge3/pkgs",
            home + "/anaconda3/pkgs",
            home + "/opt/miniconda3/pkgs",
            home + "/mambaforge/pkgs"
        ]
        var items: [ScanItem] = []
        var seen = Set<String>()
        for path in candidates {
            guard seen.insert(path).inserted, DevToolsFS.isDirectory(path) else { continue }
            items.append(ScanItem(
                path: path,
                sizeBytes: DevToolsFS.recursiveSize(of: path, isCancelled: { Task.isCancelled }),
                sourceDetectorID: "dev.python.conda-pkgs-cache",
                category: "Python — conda/mamba package cache",
                lastUsed: DevToolsFS.modificationDate(path).map { LastUsedEvidence(date: $0, source: .filesystemMTime) },
                reason: "conda/mamba's extracted-package cache at \(path), shared across environments. conda re-fetches/re-links packages from here as needed; safe to clear (or run `conda clean --packages`)."
            ))
        }
        return items
    }

    // MARK: - virtualenvs

    private func scanVirtualenvContainers(home: String) -> [ScanItem] {
        let containers = [
            home + "/.virtualenvs",
            home + "/venvs",
            home + "/Library/Caches/pypoetry/virtualenvs",
            home + "/.cache/pypoetry/virtualenvs",
            home + "/.local/share/virtualenvs"
        ]
        var items: [ScanItem] = []
        for container in containers {
            guard DevToolsFS.isDirectory(container) else { continue }
            for name in DevToolsFS.directoryEntries(container) {
                let venvPath = container + "/" + name
                guard DevToolsFS.isDirectory(venvPath) else { continue }
                guard DevToolsFS.exists(venvPath + "/pyvenv.cfg") else { continue }
                items.append(contentsOf: evaluateVirtualenv(at: venvPath))
            }
        }
        return items
    }

    private func evaluateVirtualenv(at venvPath: String) -> [ScanItem] {
        let mtime = DevToolsFS.modificationDate(venvPath)
        let size = DevToolsFS.recursiveSize(of: venvPath, isCancelled: { Task.isCancelled })
        let evidence = mtime.map { LastUsedEvidence(date: $0, source: .filesystemMTime) }

        // pipenv (and some virtualenvwrapper setups) write a `.project` file
        // inside the venv recording the absolute path of the project it
        // belongs to — the strongest signal we have for "orphaned".
        let projectMarker = venvPath + "/.project"
        if DevToolsFS.exists(projectMarker),
           let recorded = try? String(contentsOfFile: projectMarker, encoding: .utf8) {
            let projectPath = recorded.trimmingCharacters(in: .whitespacesAndNewlines)
            if !projectPath.isEmpty, !DevToolsFS.exists(projectPath) {
                return [ScanItem(
                    path: venvPath,
                    sizeBytes: size,
                    sourceDetectorID: "dev.python.orphaned-virtualenv",
                    category: "Python — orphaned virtualenv",
                    lastUsed: evidence,
                    reason: "Virtualenv's .project marker records its owning project as \(projectPath), which no longer exists on disk — this environment is orphaned and safe to remove."
                )]
            }
            // Marker points at a project that still exists — not orphaned.
            return []
        }

        // No marker to check against (e.g. a plain poetry/virtualenvwrapper
        // venv): best-effort only. Flag as a *candidate* if stale, phrased
        // so the UI doesn't overstate confidence.
        if let mtime, now().timeIntervalSince(mtime) >= staleVirtualenvThreshold {
            return [ScanItem(
                path: venvPath,
                sizeBytes: size,
                sourceDetectorID: "dev.python.stale-virtualenv-candidate",
                category: "Python — possibly orphaned virtualenv",
                lastUsed: evidence,
                reason: "Has a pyvenv.cfg but no .project marker to confirm its owning project, and hasn't been modified in \(daysText(staleVirtualenvThreshold)). Best-effort heuristic only — review before removing, not a confirmed orphan."
            )]
        }
        return []
    }

    // MARK: - Jupyter

    private func scanJupyterCache(home: String) -> [ScanItem] {
        let candidates = [home + "/.cache/jupyter", home + "/.local/share/jupyter"]
        var items: [ScanItem] = []
        for path in candidates {
            guard DevToolsFS.isDirectory(path) else { continue }
            items.append(ScanItem(
                path: path,
                sizeBytes: DevToolsFS.recursiveSize(of: path, isCancelled: { Task.isCancelled }),
                sourceDetectorID: "dev.python.jupyter-cache",
                category: "Python — Jupyter cache",
                lastUsed: DevToolsFS.modificationDate(path).map { LastUsedEvidence(date: $0, source: .filesystemMTime) },
                reason: "Jupyter's runtime/kernel-connection and data directory (\(path)). Recreated automatically the next time Jupyter runs; safe to clear."
            ))
        }
        return items
    }

    // MARK: - stray __pycache__

    private func scanStrayPycache(home: String) -> [ScanItem] {
        let matches = DevToolsFS.findDirectories(
            under: home,
            maxDepth: 8,
            skipping: [".git", "Library", ".Trash", "node_modules"],
            isCancelled: { Task.isCancelled }
        ) { name, _ in name == "__pycache__" }

        return matches.map { path in
            ScanItem(
                path: path,
                sizeBytes: DevToolsFS.recursiveSize(of: path, isCancelled: { Task.isCancelled }),
                sourceDetectorID: "dev.python.pycache",
                category: "Python — __pycache__",
                lastUsed: DevToolsFS.modificationDate(path).map { LastUsedEvidence(date: $0, source: .filesystemMTime) },
                reason: "Compiled Python bytecode cache. Regenerated automatically the next time the corresponding .py files are imported; always safe to remove."
            )
        }
    }
}
