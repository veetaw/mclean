import Foundation
import CoreScanEngine

/// Finds Ruby toolchain caches and unused version-manager installs:
/// - gem caches (`~/.gem`, plus per-version caches under rbenv/rvm)
/// - rbenv/rvm-managed Ruby versions that aren't the configured default and
///   haven't been touched in a while (best-effort — see reason text)
///
/// Strictly read-only. See `CoreScanEngine.Detector`.
public struct RubyDetector: Detector {
    public let id = "dev.ruby"
    public let displayName = "Ruby"
    public let category: DetectorCategory = .devTools

    private let staleVersionThreshold: TimeInterval
    private let now: @Sendable () -> Date

    public init(
        staleVersionThreshold: TimeInterval = 180 * 24 * 3600,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.staleVersionThreshold = staleVersionThreshold
        self.now = now
    }

    public func scan(context: ScanContext) async throws -> [ScanItem] {
        var items: [ScanItem] = []
        for home in HomeDirectories.resolve(context) {
            if Task.isCancelled { break }
            items.append(contentsOf: scanGemCaches(home: home))
            items.append(contentsOf: scanUnusedVersions(
                home: home,
                managerDir: home + "/.rbenv/versions",
                globalVersionFile: home + "/.rbenv/version",
                managerLabel: "rbenv"
            ))
            items.append(contentsOf: scanUnusedVersions(
                home: home,
                managerDir: home + "/.rvm/rubies",
                globalVersionFile: home + "/.rvm/config/default",
                managerLabel: "rvm"
            ))
        }
        return items
    }

    // MARK: - gem caches

    private func scanGemCaches(home: String) -> [ScanItem] {
        var items: [ScanItem] = []

        let simpleCache = home + "/.gem"
        if DevToolsFS.isDirectory(simpleCache) {
            items.append(ScanItem(
                path: simpleCache,
                sizeBytes: DevToolsFS.recursiveSize(of: simpleCache, isCancelled: { Task.isCancelled }),
                sourceDetectorID: "dev.ruby.gem-home-cache",
                category: "Ruby — gem cache",
                lastUsed: DevToolsFS.modificationDate(simpleCache).map { LastUsedEvidence(date: $0, source: .filesystemMTime) },
                reason: "User-level RubyGems home/cache (~/.gem). `gem install`/`bundle install` re-download gems as needed; safe to clear."
            ))
        }

        for managerRoot in [home + "/.rbenv/versions", home + "/.rvm/rubies"] {
            guard DevToolsFS.isDirectory(managerRoot) else { continue }
            for versionName in DevToolsFS.directoryEntries(managerRoot) {
                let gemsRoot = managerRoot + "/" + versionName + "/lib/ruby/gems"
                guard DevToolsFS.isDirectory(gemsRoot) else { continue }
                for gemVersion in DevToolsFS.directoryEntries(gemsRoot) {
                    let cacheDir = gemsRoot + "/" + gemVersion + "/cache"
                    guard DevToolsFS.isDirectory(cacheDir) else { continue }
                    items.append(ScanItem(
                        path: cacheDir,
                        sizeBytes: DevToolsFS.recursiveSize(of: cacheDir, isCancelled: { Task.isCancelled }),
                        sourceDetectorID: "dev.ruby.gem-version-cache",
                        category: "Ruby — gem cache",
                        lastUsed: DevToolsFS.modificationDate(cacheDir).map { LastUsedEvidence(date: $0, source: .filesystemMTime) },
                        reason: "Downloaded .gem archives cached for Ruby \(versionName). RubyGems/Bundler re-download as needed; safe to clear."
                    ))
                }
            }
        }
        return items
    }

    // MARK: - unused rbenv/rvm versions

    private func scanUnusedVersions(
        home: String,
        managerDir: String,
        globalVersionFile: String,
        managerLabel: String
    ) -> [ScanItem] {
        guard DevToolsFS.isDirectory(managerDir) else { return [] }
        let globalVersion = (try? String(contentsOfFile: globalVersionFile, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var items: [ScanItem] = []
        for versionName in DevToolsFS.directoryEntries(managerDir) {
            if versionName == globalVersion { continue }
            let path = managerDir + "/" + versionName
            guard DevToolsFS.isDirectory(path) else { continue }
            guard let mtime = DevToolsFS.modificationDate(path),
                  now().timeIntervalSince(mtime) >= staleVersionThreshold else { continue }

            items.append(ScanItem(
                path: path,
                sizeBytes: DevToolsFS.recursiveSize(of: path, isCancelled: { Task.isCancelled }),
                sourceDetectorID: "dev.ruby.unused-\(managerLabel)-version",
                category: "Ruby — unused \(managerLabel) version",
                lastUsed: LastUsedEvidence(date: mtime, source: .filesystemMTime),
                reason: "Ruby \(versionName), installed via \(managerLabel), is not the configured default version and hasn't been touched in \(daysText(staleVersionThreshold)). Best-effort: this cannot see per-project `.ruby-version` pins, so verify no project still targets this version before removing; reinstallable via \(managerLabel) if needed again."
            ))
        }
        return items
    }
}
