import Foundation

/// Swifter's route handlers are synchronous closures `(HttpRequest) ->
/// HttpResponse`, each invoked on its own dedicated background thread from
/// Swifter's own dispatch pool (see `HttpServerIO.handleConnection`) —
/// there's no `async` entry point to hook into. This bridges one call into
/// `RemoteControlServer`'s async core logic (the `PairingStore`,
/// `QuarantineManaging`, and `ScanSnapshotProviding` dependencies are all
/// `async`) by blocking the calling thread on a semaphore until the `Task`
/// finishes.
///
/// This is safe here because:
/// 1. Each HTTP connection already owns its own thread for the lifetime of
///    the request in Swifter's model, so blocking it doesn't stall any
///    other connection or any UI thread.
/// 2. `DispatchSemaphore.wait()`/`signal()` establishes the happens-before
///    edge needed to safely read `box.value` after `wait()` returns, so the
///    `@unchecked Sendable` box below never has a real data race — the
///    write on the `Task` and the read after `wait()` can never overlap.
func runBlocking<T: Sendable>(_ operation: @escaping @Sendable () async -> T) -> T {
    let semaphore = DispatchSemaphore(value: 0)
    let box = ResultBox<T>()
    Task {
        box.value = await operation()
        semaphore.signal()
    }
    semaphore.wait()
    return box.value!
}

private final class ResultBox<T>: @unchecked Sendable {
    var value: T?
}
