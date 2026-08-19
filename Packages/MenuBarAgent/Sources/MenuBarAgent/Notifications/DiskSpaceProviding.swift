import Foundation

public enum DiskSpaceError: Error, Sendable, Equatable {
    case statfsFailed(errno: Int32)
}

/// Abstraction over "how much free space is left on this volume", so
/// `LowDiskSpaceMonitor` (and `SystemStatsProvider`) can be tested with a
/// fake provider instead of depending on the real volume's actual free
/// space.
public protocol DiskSpaceProviding: Sendable {
    /// Returns (free, total) bytes for the volume containing `path`.
    func freeAndTotalBytes(atPath path: String) throws -> (free: Int64, total: Int64)
}

/// Real implementation, backed by `statfs(2)`.
public struct StatfsDiskSpaceProvider: DiskSpaceProviding {
    public init() {}

    public func freeAndTotalBytes(atPath path: String) throws -> (free: Int64, total: Int64) {
        var info = statfs()
        guard statfs(path, &info) == 0 else {
            throw DiskSpaceError.statfsFailed(errno: errno)
        }
        let blockSize = Int64(info.f_bsize)
        // f_bavail (blocks available to a non-superuser) is what a real user
        // can actually use, unlike f_bfree which also counts
        // superuser-reserved blocks.
        let free = Int64(info.f_bavail) * blockSize
        let total = Int64(info.f_blocks) * blockSize
        return (free, total)
    }
}
