import Foundation

/// The outcome of one subprocess invocation made on behalf of a
/// `MaintenanceTask`.
///
/// Captures stdout, stderr, and exactly how the process ended — a clean
/// exit with a status code, a hard timeout, or a launch failure (binary
/// missing, permission denied, etc.) — so a `MaintenanceTask` can build an
/// honest, specific `MaintenanceTaskResult` instead of a bare true/false.
public struct MaintenanceCommandOutcome: Sendable, Equatable {
    public enum Status: Sendable, Equatable {
        /// The process ran to completion. `code == 0` conventionally means
        /// success; anything else is command-specific failure.
        case exited(code: Int32)
        /// The process was still running after the caller's timeout and was
        /// forcibly terminated. Never let a hung subprocess hang the caller.
        case timedOut
        /// `Process.run()` itself threw (e.g. the executable path doesn't
        /// exist). No process ever started.
        case launchFailed(reason: String)
    }

    public let status: Status
    public let standardOutput: String
    public let standardError: String

    public init(status: Status, standardOutput: String, standardError: String) {
        self.status = status
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

    /// True only for a clean, zero-exit-code completion.
    public var succeeded: Bool {
        if case .exited(let code) = status, code == 0 { return true }
        return false
    }
}

/// Abstraction over "run this fixed executable with these fixed arguments,"
/// so `MaintenanceTask` implementations never talk to `Process` directly.
///
/// This exists for exactly one reason: tests. Every real
/// `MaintenanceTask.run(using:)` call in the shipping app uses
/// `LiveMaintenanceCommandRunner`, which actually shells out. Tests inject a
/// fake conforming type instead, so they can assert on the *exact* command
/// and arguments a task builds — including the one hardcoded AppleScript
/// string for the Spotlight elevation case — without ever executing a real
/// process, prompting for a password, or touching the real system's DNS
/// cache, Spotlight index, or font cache.
///
/// `executable` and `arguments` are always fixed, hardcoded literals chosen
/// by the `MaintenanceTask` itself (see each task's doc comment) — never
/// built from user input, file contents, or any other data this package
/// doesn't control. There is no code path from an arbitrary string to
/// execution here.
public protocol MaintenanceCommandRunning: Sendable {
    func run(executable: String, arguments: [String], timeout: TimeInterval) async -> MaintenanceCommandOutcome
}

extension MaintenanceCommandOutcome {
    /// Human-readable one-liner for whatever ended this command, used to
    /// build a `MaintenanceTaskResult.summary` when the command itself
    /// didn't exit cleanly.
    var failureDescription: String {
        switch status {
        case .exited(let code):
            return "exited with status \(code)"
        case .timedOut:
            return "timed out"
        case .launchFailed(let reason):
            return "could not be launched (\(reason))"
        }
    }

    /// Combined stdout+stderr, trimmed, for inclusion in a task's `output`.
    var combinedOutput: String {
        [standardOutput, standardError]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
