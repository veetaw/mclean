import Foundation

/// Abstraction over "run an external command-line tool and capture stdout",
/// so detectors that shell out (only `SimulatorRuntimeDetector`, via
/// `xcrun simctl`) can be unit-tested without depending on Xcode actually
/// being installed on the test machine.
public protocol CommandRunning: Sendable {
    /// Runs `executablePath` with `arguments` and returns captured stdout.
    /// Throws `CommandRunningError.executableNotFound` if `executablePath`
    /// doesn't exist/isn't executable, so callers can degrade gracefully
    /// (return no items) rather than surface a scary process-launch error.
    func run(executablePath: String, arguments: [String]) throws -> String
}

public enum CommandRunningError: Error {
    case executableNotFound(String)
    case nonZeroExit(Int32, stderr: String)
}

/// Real implementation, backed by `Foundation.Process`. Strictly read-only:
/// only ever invokes read/list style subcommands (`simctl list ... -j`).
public struct ProcessCommandRunner: CommandRunning {
    public init() {}

    public func run(executablePath: String, arguments: [String]) throws -> String {
        guard FileManager.default.isExecutableFile(atPath: executablePath) else {
            throw CommandRunningError.executableNotFound(executablePath)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stderrString = String(data: stderrData, encoding: .utf8) ?? ""
            throw CommandRunningError.nonZeroExit(process.terminationStatus, stderr: stderrString)
        }

        return String(data: stdoutData, encoding: .utf8) ?? ""
    }
}
