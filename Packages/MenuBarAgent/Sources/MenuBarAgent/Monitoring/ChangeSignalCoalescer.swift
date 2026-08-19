import Foundation

/// Coalesces bursts of filesystem-change signals into a single async
/// `onFire` call after `quietPeriod` of silence, so a "maybe re-scan" signal
/// fires once per burst of filesystem activity rather than once per raw
/// FSEvents callback -- this is the piece that keeps background monitoring's
/// CPU/energy footprint minimal.
///
/// Actor-isolated so it can be driven safely from the FSEvents C callback
/// (which arrives on an arbitrary dispatch queue, never on a Swift
/// concurrency executor) via a plain `Task { await recordEvent() }` hop, with
/// no manual locking anywhere in this type.
public actor ChangeSignalCoalescer {
    private var coalescer: EventCoalescer
    private let clock: Clock
    private let sleeper: Sleeping
    private var pendingCheck: Task<Void, Never>?
    private let onFire: @Sendable () async -> Void

    public init(
        quietPeriod: TimeInterval,
        clock: Clock = SystemClock(),
        sleeper: Sleeping = TaskSleeper(),
        onFire: @escaping @Sendable () async -> Void
    ) {
        self.coalescer = EventCoalescer(quietPeriod: quietPeriod)
        self.clock = clock
        self.sleeper = sleeper
        self.onFire = onFire
    }

    /// Record a raw event and (re)schedule the quiet-period check. Cheap and
    /// safe to call at high frequency: each call just cancels and replaces
    /// the pending check task, so a burst of events collapses into a single
    /// eventual `onFire`.
    public func recordEvent() {
        coalescer.recordEvent(at: clock.now())
        pendingCheck?.cancel()
        let quietPeriod = coalescer.quietPeriod
        pendingCheck = Task { [weak self, sleeper] in
            await sleeper.sleep(for: quietPeriod)
            guard !Task.isCancelled else { return }
            await self?.checkAndFire()
        }
    }

    private func checkAndFire() async {
        guard coalescer.shouldFire(at: clock.now()) else { return }
        await onFire()
    }

    /// Cancels any pending check without firing. Call when stopping
    /// monitoring so no stray signal fires after the caller has moved on.
    public func cancel() {
        pendingCheck?.cancel()
        pendingCheck = nil
    }
}
