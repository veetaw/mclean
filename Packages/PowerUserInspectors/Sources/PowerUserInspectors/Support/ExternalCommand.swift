import Foundation

/// Injectable, testable abstraction over "run an external command-line tool
/// and capture its output" — the same shape used by
/// `DevToolsDetectors.ExternalProcess` and `MobileDevDetectors.CommandRunning`,
/// reimplemented locally so this package doesn't take on either sibling
/// package as a dependency (see `ARCHITECTURE.md`).
///
/// Every part of this package that shells out (TCC database reads via
/// `sqlite3`, package-manager listings, Spotlight metadata via `mdls`) goes
/// through this protocol. Conforming implementations must be:
///
/// - **read-only**: only ever invoke list/read/query-style subcommands,
///   never anything that installs, uninstalls, writes, or mutates state;
/// - **bounded**: always apply a timeout, so a hung or missing tool never
///   blocks a caller indefinitely;
/// - **non-throwing**: failures (binary missing, timeout, launch error)
///   surface as `nil`, never a thrown error — callers degrade to "nothing to
///   report" rather than propagate a scary process-launch error.
///
/// A non-zero exit is *not* collapsed into `nil` — it's reported via
/// `ExternalCommandResult.exitCode` — since some read-only tools (e.g.
/// `npm ls -g` with peer-dependency warnings) exit non-zero while still
/// printing perfectly usable output on stdout, and some callers (the TCC
/// reader) need to distinguish "tool ran but query failed" from "tool
/// couldn't be launched at all".
protocol ExternalCommandRunning: Sendable {
    func run(
        executable: String,
        arguments: [String],
        currentDirectory: String?,
        timeout: TimeInterval
    ) async -> ExternalCommandResult?
}

struct ExternalCommandResult: Sendable, Equatable {
    let standardOutput: String
    let standardError: String
    let exitCode: Int32
}

/// Real implementation, backed by `Foundation.Process`, launched via
/// `/usr/bin/env <executable>` so PATH-based lookup resolves tools installed
/// by Homebrew, pyenv, nvm, rustup, etc. rather than requiring a hardcoded
/// absolute path for every tool.
struct RealExternalCommandRunner: ExternalCommandRunning {
    init() {}

    func run(
        executable: String,
        arguments: [String],
        currentDirectory: String?,
        timeout: TimeInterval
    ) async -> ExternalCommandResult? {
        await withCheckedContinuation { (continuation: CheckedContinuation<ExternalCommandResult?, Never>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [executable] + arguments
            if let currentDirectory {
                process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)
            }

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            let resolver = ExternalCommandContinuationResolver(continuation)

            process.terminationHandler = { proc in
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let result = ExternalCommandResult(
                    standardOutput: String(data: outData, encoding: .utf8) ?? "",
                    standardError: String(data: errData, encoding: .utf8) ?? "",
                    exitCode: proc.terminationStatus
                )
                Task { await resolver.resolve(result) }
            }

            do {
                try process.run()
            } catch {
                Task { await resolver.resolve(nil) }
                return
            }

            Task {
                try? await Task.sleep(nanoseconds: UInt64(max(timeout, 0.1) * 1_000_000_000))
                if process.isRunning {
                    process.terminate()
                }
            }
        }
    }
}

/// Guarantees a `CheckedContinuation` is resumed exactly once, even though
/// both the termination handler and a slow-path timeout could in principle
/// race to resolve it.
private actor ExternalCommandContinuationResolver {
    private var didResume = false
    private let continuation: CheckedContinuation<ExternalCommandResult?, Never>

    init(_ continuation: CheckedContinuation<ExternalCommandResult?, Never>) {
        self.continuation = continuation
    }

    func resolve(_ value: ExternalCommandResult?) {
        guard !didResume else { return }
        didResume = true
        continuation.resume(returning: value)
    }
}
