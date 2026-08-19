import Foundation

/// The real `MaintenanceCommandRunning` implementation: launches `Process`
/// directly at the given absolute executable path, captures stdout/stderr,
/// and hard-kills the process if it hasn't finished within `timeout`.
///
/// Modeled on `DevToolsDetectors/Support/ExternalProcess.swift`'s
/// timeout-via-race approach, with two differences that matter for
/// maintenance actions rather than read-only detection:
///
/// - Both stdout *and* stderr are always captured and returned (detection
///   only needed stdout on success); a maintenance task's failure output is
///   exactly what the user needs to see when a command didn't work.
/// - Failure is reported as data (`MaintenanceCommandOutcome`), never by
///   throwing — a missing binary, a non-zero exit, or a timeout are all
///   ordinary, expected outcomes a `MaintenanceTask` turns into a clear
///   failure message, not a crash.
public struct LiveMaintenanceCommandRunner: MaintenanceCommandRunning {
    public init() {}

    public func run(executable: String, arguments: [String], timeout: TimeInterval) async -> MaintenanceCommandOutcome {
        await withCheckedContinuation { (continuation: CheckedContinuation<MaintenanceCommandOutcome, Never>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            let resolver = MaintenanceCommandResolver(continuation)

            process.terminationHandler = { proc in
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let outcome = MaintenanceCommandOutcome(
                    status: .exited(code: proc.terminationStatus),
                    standardOutput: String(data: outData, encoding: .utf8) ?? "",
                    standardError: String(data: errData, encoding: .utf8) ?? ""
                )
                Task { await resolver.resolve(outcome) }
            }

            do {
                try process.run()
            } catch {
                let outcome = MaintenanceCommandOutcome(
                    status: .launchFailed(reason: error.localizedDescription),
                    standardOutput: "",
                    standardError: ""
                )
                Task { await resolver.resolve(outcome) }
                return
            }

            Task {
                try? await Task.sleep(nanoseconds: UInt64(max(timeout, 0.1) * 1_000_000_000))
                if process.isRunning {
                    process.terminate()
                    let outcome = MaintenanceCommandOutcome(
                        status: .timedOut,
                        standardOutput: "",
                        standardError: ""
                    )
                    Task { await resolver.resolve(outcome) }
                }
            }
        }
    }
}

/// Guarantees a `CheckedContinuation` is resumed exactly once, even though
/// the termination handler and the timeout task could in principle race to
/// resolve it. Mirrors `DevToolsDetectors`' `ContinuationResolver`.
private actor MaintenanceCommandResolver {
    private var didResume = false
    private let continuation: CheckedContinuation<MaintenanceCommandOutcome, Never>

    init(_ continuation: CheckedContinuation<MaintenanceCommandOutcome, Never>) {
        self.continuation = continuation
    }

    func resolve(_ value: MaintenanceCommandOutcome) {
        guard !didResume else { return }
        didResume = true
        continuation.resume(returning: value)
    }
}
