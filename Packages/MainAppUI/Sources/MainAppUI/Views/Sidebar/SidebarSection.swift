import Foundation

/// Top-level sidebar destinations. `remoteControl` is filtered out of the
/// visible list entirely (not just disabled) when
/// `Capabilities.canRunRemoteControlServer` is `false` — see `ContentView`.
enum SidebarSection: String, CaseIterable, Identifiable, Hashable {
    case dashboard
    case systemJunk
    case devTools
    case mobileDev
    case powerUser
    case quarantine
    case shredder
    case remoteControl
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .systemJunk: "System Junk"
        case .devTools: "Developer Tools"
        case .mobileDev: "Mobile Dev"
        case .powerUser: "Power User"
        case .quarantine: "Quarantine"
        case .shredder: "Shredder"
        case .remoteControl: "Remote Control"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: "gauge.with.dots.needle.50percent"
        case .systemJunk: "trash"
        case .devTools: "hammer"
        case .mobileDev: "iphone.gen3"
        case .powerUser: "wrench.and.screwdriver"
        case .quarantine: "xmark.bin"
        case .shredder: "scissors"
        case .remoteControl: "wifi"
        case .settings: "gearshape"
        }
    }
}
