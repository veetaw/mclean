import Foundation
#if canImport(ServiceManagement)
import ServiceManagement
#endif

/// Mirrors `SMAppService.Status` as a plain, `Sendable`, testable value —
/// this package's public surface never leaks `ServiceManagement` types
/// directly so callers don't need to import it just to read a status.
public enum LoginItemStatus: String, Sendable, Hashable, Codable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
    /// A status this package doesn't recognize (future SDK addition).
    case unknown
}

#if canImport(ServiceManagement)
@available(macOS 13.0, *)
extension LoginItemStatus {
    init(_ status: SMAppService.Status) {
        switch status {
        case .notRegistered: self = .notRegistered
        case .enabled: self = .enabled
        case .requiresApproval: self = .requiresApproval
        case .notFound: self = .notFound
        @unknown default: self = .unknown
        }
    }
}
#endif
