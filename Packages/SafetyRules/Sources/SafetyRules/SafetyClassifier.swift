import CoreScanEngine
import Foundation

/// Default `SafetyClassifying` implementation: checks the hardcoded
/// `Denylist` first, unconditionally, then falls back to
/// `needsConfirmation` for everything else.
///
/// It deliberately does **not** yet evaluate `safe-auto` rules from a
/// user-editable rule file — `RuleSetDraft.swift` sketches that format but
/// it's still pending user review (checkpoint 4, see ARCHITECTURE.md).
/// Wiring in `safeAuto` matching is a follow-up once that format is
/// finalized; until then every non-forbidden item requires explicit
/// confirmation, which is the safe default.
public struct SafetyClassifier: SafetyClassifying {
    public init() {}

    public func classify(_ item: ScanItem) -> SafetyVerdict {
        if let reason = Denylist.forbiddenReason(forPath: item.path) {
            return .forbidden(ruleID: "denylist.path", reason: reason)
        }
        if Denylist.isLikelyBootVolumeRoot(item.path) {
            return .forbidden(ruleID: "denylist.boot-volume-root", reason: "Path is a volume root.")
        }
        return .needsConfirmation(reason: "No safe-auto rule matched; default policy requires confirmation.")
    }
}
