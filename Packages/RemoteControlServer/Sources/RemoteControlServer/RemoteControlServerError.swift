import Foundation

public enum RemoteControlServerError: Error, Sendable, Equatable, CustomStringConvertible {
    case alreadyRunning
    case notRunning

    public var description: String {
        switch self {
        case .alreadyRunning: return "RemoteControlServer is already running."
        case .notRunning: return "RemoteControlServer is not running."
        }
    }
}
