import Foundation
import CoreScanEngine

/// Finds Docker artifacts that are typically safe to reclaim — dangling
/// (untagged) images, orphaned volumes, and reclaimable build cache — by
/// shelling out to the `docker` CLI, since none of this is enumerable by
/// walking the filesystem (Docker Desktop stores everything inside its own
/// Linux VM, invisible from the host filesystem).
///
/// If `docker` isn't installed or isn't responding, `scan` simply returns no
/// items — it never throws for that reason. This detector never invokes any
/// mutating `docker` subcommand (`prune`, `rm`, `rmi`, ...); it only reads
/// (`images`, `volume ls`, `system df`). Every item's `reason` carries an
/// explicit warning, since — unlike a plain cache directory — Docker
/// resources can represent in-progress container/volume state that a naive
/// "just delete it" flow would destroy.
public struct DockerDetector: Detector {
    public let id = "dev.docker"
    public let displayName = "Docker"
    public let category: DetectorCategory = .devTools

    static let warning = "WARNING: Docker cleanup can be destructive to in-progress work — dangling images, volumes, and build cache can still be the only copy of data a stopped/removed container relied on. This detector only reads Docker's state; nothing here is deleted automatically, and any removal should go through `docker` itself (e.g. `docker image prune`), not a filesystem delete."

    /// Injectable so tests can point `PATH` (and thus `/usr/bin/env docker`)
    /// at a fake `docker` script instead of requiring Docker to be installed.
    private let environment: [String: String]

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.environment = environment
    }

    public func scan(context: ScanContext) async throws -> [ScanItem] {
        guard await isDockerAvailable() else { return [] }
        if Task.isCancelled { return [] }

        var items: [ScanItem] = []
        items.append(contentsOf: await scanDanglingImages())
        if Task.isCancelled { return items }
        items.append(contentsOf: await scanDanglingVolumes())
        if Task.isCancelled { return items }
        items.append(contentsOf: await scanBuildCache())
        return items
    }

    private func isDockerAvailable() async -> Bool {
        await ExternalProcess.run(executable: "docker", arguments: ["--version"], environment: environment) != nil
    }

    private func scanDanglingImages() async -> [ScanItem] {
        guard let output = await ExternalProcess.run(
            executable: "docker",
            arguments: ["images", "--filter", "dangling=true", "--format", "{{.ID}}\t{{.Size}}\t{{.CreatedSince}}"],
            environment: environment
        ) else { return [] }

        var items: [ScanItem] = []
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard let imageID = fields.first, !imageID.isEmpty else { continue }
            let sizeText = fields.count > 1 ? fields[1] : "unknown size"
            let created = fields.count > 2 ? fields[2] : "unknown age"
            items.append(ScanItem(
                path: "docker://image/\(imageID)",
                sizeBytes: nil,
                sourceDetectorID: "dev.docker.dangling-image",
                category: "Docker — dangling image",
                lastUsed: nil,
                reason: "\(Self.warning) Dangling (untagged) image \(imageID), reported size \(sizeText), created \(created). Remove via `docker image prune`."
            ))
        }
        return items
    }

    private func scanDanglingVolumes() async -> [ScanItem] {
        guard let output = await ExternalProcess.run(
            executable: "docker",
            arguments: ["volume", "ls", "--filter", "dangling=true", "--format", "{{.Name}}"],
            environment: environment
        ) else { return [] }

        var items: [ScanItem] = []
        for line in output.split(separator: "\n") {
            let name = line.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            items.append(ScanItem(
                path: "docker://volume/\(name)",
                sizeBytes: nil,
                sourceDetectorID: "dev.docker.dangling-volume",
                category: "Docker — orphaned volume",
                lastUsed: nil,
                reason: "\(Self.warning) Volume '\(name)' is not attached to any container. It may still hold data from a stopped or removed container someone intends to restart. Remove via `docker volume prune`."
            ))
        }
        return items
    }

    private func scanBuildCache() async -> [ScanItem] {
        guard let output = await ExternalProcess.run(
            executable: "docker",
            arguments: ["system", "df", "--format", "{{json .}}"],
            environment: environment
        ) else { return [] }

        for line in output.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = object["Type"] as? String,
                  type == "Build Cache" else { continue }

            let reclaimable = (object["Reclaimable"] as? String) ?? "an unknown amount"
            return [ScanItem(
                path: "docker://build-cache",
                sizeBytes: nil,
                sourceDetectorID: "dev.docker.build-cache",
                category: "Docker — build cache",
                lastUsed: nil,
                reason: "\(Self.warning) Docker reports \(reclaimable) of reclaimable build cache. Remove via `docker builder prune`."
            )]
        }
        return []
    }
}
