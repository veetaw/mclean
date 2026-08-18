import CoreScanEngine
import Foundation

/// The outcome of classifying a `ScanItem` against the safety rule set.
/// This is the single choke point every deletion-adjacent code path in the
/// app must consult before offering (let alone performing) any action.
public enum SafetyVerdict: Sendable, Hashable, Codable {
    /// Matches the hardcoded, non-configurable denylist. Never offered for
    /// deletion, full stop — not even behind confirmation. See `Denylist`.
    case forbidden(ruleID: String, reason: String)

    /// Matches a versioned, user-inspectable rule explicitly marked
    /// `safe-auto` (e.g. system temp files expired for N+ days). May be
    /// deleted without a per-item confirmation dialog, but still goes
    /// through quarantine — see `SAFETY_RULES.md`.
    case safeAuto(ruleID: String)

    /// Everything else. Always requires explicit, per-item (or per-batch,
    /// user-reviewed) confirmation before moving to quarantine.
    case needsConfirmation(reason: String)
}

/// The single entry point modules should call to classify an item. The
/// concrete implementation composes the hardcoded `Denylist` (checked first,
/// unconditionally) with the loaded, user-editable rule set.
public protocol SafetyClassifying: Sendable {
    func classify(_ item: ScanItem) -> SafetyVerdict
}
