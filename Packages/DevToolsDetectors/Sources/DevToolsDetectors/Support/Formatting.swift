import Foundation

/// Renders a threshold like `90 * 24 * 3600` seconds as `"90+ days"` for use
/// in human-readable `ScanItem.reason` strings.
func daysText(_ interval: TimeInterval) -> String {
    "\(Int(interval / 86400))+ days"
}
