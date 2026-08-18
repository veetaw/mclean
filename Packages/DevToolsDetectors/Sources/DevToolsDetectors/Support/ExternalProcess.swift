import Foundation

/// Minimal helper for shelling out to an optional external CLI (currently
/// only `docker`, from `DockerDetector`), with a hard timeout so a hung or
/// missing subprocess never blocks a scan indefinitely.
///
/// Never throws — callers get `nil` on any failure (binary missing, non-zero
/// exit, timeout, launch error, etc.) and are expected to treat that as
/// "nothing to report" rather than propagate an error. This is what lets
/// `DockerDetector` stay silent (return no items) on a machine without
/// Docker installed, per the read-only/never-throw contract of `Detector`.
enum ExternalProcess {
    /// Runs `/usr/bin/env <executable> <arguments...>` — going through `env`
    /// so PATH-based lookup (including a test-injected `PATH` in
    /// `environment`) resolves the binary — and returns captured stdout on a
    /// clean (zero) exit, or `nil` otherwise.
    static func run(
        executable: String,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval = 5
    ) async -> String? {
        await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [executable] + arguments
            process.environment = environment

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            let resolver = ContinuationResolver(continuation)

            process.terminationHandler = { proc in
                let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                let output = proc.terminationStatus == 0 ? String(data: data, encoding: .utf8) : nil
                Task { await resolver.resolve(output) }
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
private actor ContinuationResolver {
    private var didResume = false
    private let continuation: CheckedContinuation<String?, Never>

    init(_ continuation: CheckedContinuation<String?, Never>) {
        self.continuation = continuation
    }

    func resolve(_ value: String?) {
        guard !didResume else { return }
        didResume = true
        continuation.resume(returning: value)
    }
}
