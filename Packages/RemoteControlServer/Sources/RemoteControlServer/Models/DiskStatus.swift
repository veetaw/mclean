import Foundation

/// Supplies free/total disk space for the `GET /api/v1/status` endpoint.
/// Injected so tests don't depend on the real disk and so the desktop app
/// can choose which volume to report (normally the boot volume).
public protocol DiskSpaceProviding: Sendable {
    func diskStatus() -> DiskStatus
}

public struct DiskStatus: Sendable, Codable, Equatable {
    public let freeBytes: Int64
    public let totalBytes: Int64

    public init(freeBytes: Int64, totalBytes: Int64) {
        self.freeBytes = freeBytes
        self.totalBytes = totalBytes
    }
}

/// Default `DiskSpaceProviding`, backed by `URLResourceKey` volume values.
/// Best-effort: returns zeros if the resource values can't be read rather
/// than throwing, since disk status is a "nice to have" display value, not
/// something any safety decision depends on.
public struct SystemDiskSpaceProvider: DiskSpaceProviding {
    private let volumeURL: URL

    public init(volumeURL: URL = URL(fileURLWithPath: NSHomeDirectory())) {
        self.volumeURL = volumeURL
    }

    public func diskStatus() -> DiskStatus {
        let keys: Set<URLResourceKey> = [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeTotalCapacityKey
        ]
        guard let values = try? volumeURL.resourceValues(forKeys: keys) else {
            return DiskStatus(freeBytes: 0, totalBytes: 0)
        }
        let free = values.volumeAvailableCapacityForImportantUsage ?? 0
        let total = Int64(values.volumeTotalCapacity ?? 0)
        return DiskStatus(freeBytes: free, totalBytes: total)
    }
}
