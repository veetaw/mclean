import CoreServices
import Foundation

/// Watches one or more directories for filesystem changes using FSEvents
/// (kernel-level change notifications pushed to us), instead of polling the
/// filesystem on a timer -- this is what keeps background monitoring's
/// CPU/energy footprint minimal ("impatto CPU/energia minimo").
///
/// Raw events are coalesced by `ChangeSignalCoalescer` into a single "maybe
/// re-scan" signal per burst of activity, rather than firing `onChange` once
/// per filesystem event.
///
/// ## Concurrency bridging (read this before touching this file)
///
/// `FSEventStreamCallback` is a plain C function pointer: it cannot capture
/// Swift context, and it fires on whatever dispatch queue the stream is
/// scheduled on -- never on a Swift-concurrency executor, and never
/// synchronized with this actor's isolation. Getting from "arbitrary C
/// callback invocation" to "safely mutate actor-isolated Swift state"
/// requires three separate pieces, all present below:
///
/// 1. **Passing `self` across the C boundary.** `FSEventStreamContext.info`
///    carries an `Unmanaged.passRetained(self)` pointer to this actor, with a
///    C `release` callback that balances the retain when the stream is
///    released. This keeps the watcher alive for exactly as long as the
///    underlying FSEventStream needs it -- there is no use-after-free window,
///    and no reliance on the app happening to keep its own strong reference
///    alive for the stream's lifetime.
/// 2. **Recovering `self` inside the callback.** The free function
///    `fsEventsRawCallback` below has zero captures and matches
///    `FSEventStreamCallback`'s exact C signature (required for it to be
///    usable as a `@convention(c)` function pointer at all). It recovers the
///    actor reference via `Unmanaged.fromOpaque(...).takeUnretainedValue()`
///    and immediately hands off to a `nonisolated` method.
/// 3. **Hopping into actor isolation.** `handleRawEvent()` is `nonisolated`
///    because it is invoked synchronously from a non-Swift-concurrency
///    thread; its only job is `Task { await coalescer.recordEvent() }` --
///    `coalescer` is an `let` (immutable, `Sendable` actor reference), so
///    reading it from the callback thread is race-free without any locking.
///    All *mutable* state this type owns (`streamRef`) is only ever touched
///    from `start()`/`stop()`, both actor-isolated methods that the C
///    callback path never calls directly.
///
/// Callers must call `stop()` before releasing the watcher: an actor's
/// `deinit` is `nonisolated` and cannot safely reach back into isolated
/// state to invalidate the stream, so there is deliberately no
/// cleanup-on-deinit here.
public actor FSEventsWatcher {
    private let watchedPaths: [String]
    private let latency: TimeInterval
    private let coalescer: ChangeSignalCoalescer
    private var streamRef: FSEventStreamRef?

    /// - Parameters:
    ///   - paths: absolute directory paths to watch, e.g. `~/Library/Caches`, `/tmp`.
    ///   - latency: FSEvents' own internal batching latency, in seconds --
    ///     how long the kernel waits to batch nearby events before delivering
    ///     them to us at all.
    ///   - quietPeriod: additional debounce applied on top of FSEvents'
    ///     latency, before `onChange` actually fires.
    ///   - onChange: called once per burst of activity. Not `@MainActor` --
    ///     hop to `@MainActor` yourself inside the closure if you need to
    ///     touch UI state.
    public init(
        paths: [String],
        latency: TimeInterval = 1.0,
        quietPeriod: TimeInterval = 2.0,
        clock: Clock = SystemClock(),
        sleeper: Sleeping = TaskSleeper(),
        onChange: @escaping @Sendable () async -> Void
    ) {
        self.watchedPaths = paths
        self.latency = latency
        self.coalescer = ChangeSignalCoalescer(
            quietPeriod: quietPeriod,
            clock: clock,
            sleeper: sleeper,
            onFire: onChange
        )
    }

    /// Starts the stream. Safe to call multiple times (no-op while already running).
    public func start() {
        guard streamRef == nil else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passRetained(self).toOpaque(),
            retain: nil,
            release: { info in
                guard let info else { return }
                Unmanaged<FSEventsWatcher>.fromOpaque(info).release()
            },
            copyDescription: nil
        )

        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer
        )

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            fsEventsRawCallback,
            &context,
            watchedPaths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        ) else {
            return
        }

        streamRef = stream
        let queue = DispatchQueue(label: "pro.mclean.menubaragent.fsevents", qos: .utility)
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    /// Stops and tears down the stream. Safe to call multiple times, and safe
    /// to call even if `start()` was never called.
    public func stop() {
        guard let stream = streamRef else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream) // balances `Unmanaged.passRetained(self)` from `start()`, via `context.release`.
        streamRef = nil
    }

    /// Entry point reached from the C callback via the unmanaged context
    /// pointer. `nonisolated` because it runs on whatever thread FSEvents
    /// calls us on; its only job is to hop back into actor isolation for the
    /// real coalescing work.
    nonisolated func handleRawEvent() {
        Task { await coalescer.recordEvent() }
    }
}

/// Free C function matching `FSEventStreamCallback`'s exact signature (a
/// `@convention(c)` function pointer cannot capture any context, which is
/// exactly why `FSEventStreamContext.info` exists for passing `self` through
/// instead). This function does no work itself beyond recovering the watcher
/// and handing off -- see the concurrency-bridging doc comment on
/// `FSEventsWatcher` above.
private func fsEventsRawCallback(
    streamRef: ConstFSEventStreamRef,
    clientCallBackInfo: UnsafeMutableRawPointer?,
    numEvents: Int,
    eventPaths: UnsafeMutableRawPointer,
    eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let clientCallBackInfo else { return }
    let watcher = Unmanaged<FSEventsWatcher>.fromOpaque(clientCallBackInfo).takeUnretainedValue()
    watcher.handleRawEvent()
}
