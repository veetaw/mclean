import Foundation

/// Renders a threshold like `14 * 24 * 3600` seconds as `"14+ days"` for use
/// in human-readable `ScanItem.reason` strings.
func daysText(_ interval: TimeInterval) -> String {
    "\(Int(interval / 86400))+ days"
}

/// Renders a byte count (or `nil`, when a size couldn't be computed) in the
/// same human-readable style Finder uses, for `ScanItem.reason` strings.
func byteCountText(_ bytes: Int64?) -> String {
    guard let bytes else { return "an unknown size" }
    return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}
