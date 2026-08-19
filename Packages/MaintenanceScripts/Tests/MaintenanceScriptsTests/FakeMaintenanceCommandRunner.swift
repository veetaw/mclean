import Foundation
@testable import MaintenanceScripts

/// Test double for `MaintenanceCommandRunning`. Never launches a real
/// process — records every invocation exactly (executable, arguments,
/// timeout) so tests can assert a `MaintenanceTask` builds precisely the
/// command it claims to, and returns a scripted `MaintenanceCommandOutcome`
/// per call (in call order) so success/failure/timeout handling can be
/// exercised deterministically without touching the real system.
actor FakeMaintenanceCommandRunner: MaintenanceCommandRunning {
    struct Invocation: Equatable {
        let executable: String
        let arguments: [String]
        let timeout: TimeInterval
    }

    private(set) var invocations: [Invocation] = []
    private let scriptedOutcomes: [MaintenanceCommandOutcome]

    /// Default outcome for any call beyond the scripted list — a clean
    /// zero-exit success, so a test that only cares about the first call in
    /// a multi-command task doesn't need to script every later one.
    private static let defaultOutcome = MaintenanceCommandOutcome(
        status: .exited(code: 0),
        standardOutput: "",
        standardError: ""
    )

    init(outcomes: [MaintenanceCommandOutcome]) {
        self.scriptedOutcomes = outcomes
    }

    /// Convenience for a task that only ever issues one command.
    init(outcome: MaintenanceCommandOutcome) {
        self.init(outcomes: [outcome])
    }

    func run(executable: String, arguments: [String], timeout: TimeInterval) async -> MaintenanceCommandOutcome {
        let index = invocations.count
        invocations.append(Invocation(executable: executable, arguments: arguments, timeout: timeout))
        return index < scriptedOutcomes.count ? scriptedOutcomes[index] : Self.defaultOutcome
    }
}

/// Convenience factories for scripted outcomes.
extension MaintenanceCommandOutcome {
    static func ok(_ stdout: String = "") -> MaintenanceCommandOutcome {
        MaintenanceCommandOutcome(status: .exited(code: 0), standardOutput: stdout, standardError: "")
    }

    static func failed(code: Int32 = 1, stderr: String = "boom") -> MaintenanceCommandOutcome {
        MaintenanceCommandOutcome(status: .exited(code: code), standardOutput: "", standardError: stderr)
    }

    static let timedOutFake = MaintenanceCommandOutcome(status: .timedOut, standardOutput: "", standardError: "")

    static func launchFailedFake(reason: String = "no such file") -> MaintenanceCommandOutcome {
        MaintenanceCommandOutcome(status: .launchFailed(reason: reason), standardOutput: "", standardError: "")
    }
}
