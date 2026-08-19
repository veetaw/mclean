import Foundation

/// Optional, clearly-labeled best-effort supplement to `SMAppService`/
/// plist-based login item discovery: asks **System Events**, via
/// AppleScript, for the names of the login items it knows about.
///
/// This is a legitimate, documented, public mechanism — System Events'
/// login items list has been a standard AppleScript dictionary entry for
/// decades (`tell application "System Events" to get the name of every
/// login item`) — **not** a private/undocumented API. It is a supplement,
/// not the primary mechanism, because:
///
/// - it requires Automation permission (TCC) to control System Events,
///   which this process may not have been granted;
/// - `osascript` may be sandboxed/unavailable in some build
///   configurations;
/// - System Events' own login items list is itself just the classic
///   "Login Items" mechanism, not a complete picture of every
///   `SMAppService`-registered background item either.
///
/// Every failure mode — `osascript` missing, timeout, non-zero exit,
/// permission denial, unparsable output — degrades to `nil`. This type
/// **never** throws and never crashes the caller; a login-items report
/// that can't reach System Events just omits this supplemental section.
struct AppleScriptLoginItemsQuery: Sendable {
    private let timeout: TimeInterval

    init(timeout: TimeInterval = 5.0) {
        self.timeout = timeout
    }

    /// Returns the names System Events reports as login items, or `nil` if
    /// the query couldn't be completed for any reason.
    func queryLoginItemNames() async -> [String]? {
        let script = "tell application \"System Events\" to get the name of every login item"
        guard let output = await run(
            executable: "osascript",
            arguments: ["-e", script],
            timeout: timeout
        ) else {
            return nil
        }

        // AppleScript's `get` on a list returns a comma-space-separated
        // string, e.g. "Dropbox, Slack, Rectangle".
        let names = output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return names
    }

    private func run(executable: String, arguments: [String], timeout: TimeInterval) async -> String? {
        await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [executable] + arguments

            let outPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = Pipe()

            let resolver = AppleScriptQueryResolver(continuation)

            process.terminationHandler = { proc in
                guard proc.terminationStatus == 0 else {
                    Task { await resolver.resolve(nil) }
                    return
                }
                let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                Task { await resolver.resolve(String(data: data, encoding: .utf8)) }
            }

            do {
                try process.run()
            } catch {
                // Binary missing / launch failed — never throw, just report
                // "no result" to the caller.
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
/// race to resolve it (same pattern as
/// `PowerUserInspectors.ExternalCommandContinuationResolver`, reimplemented
/// locally per this package's no-sibling-dependency convention).
private actor AppleScriptQueryResolver {
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
