import SafetyRules
import UIDesignSystem

/// Maps a real `SafetyRules.SafetyVerdict` onto `UIDesignSystem.DSSafetyTier`
/// at the UI boundary — `UIDesignSystem` intentionally has no dependency on
/// `SafetyRules` (see `DSSafetyTier`'s doc comment), so every call site that
/// wants to render a real verdict goes through this one mapping.
extension SafetyVerdict {
    var uiTier: DSSafetyTier {
        switch self {
        case .forbidden: .forbidden
        case .safeAuto: .safeAuto
        case .needsConfirmation: .needsConfirmation
        }
    }

    /// Human-readable reason/ruleID, for detail/confirmation UI.
    var uiDetail: String {
        switch self {
        case .forbidden(let ruleID, let reason): "\(reason) (rule: \(ruleID))"
        case .safeAuto(let ruleID): "Matches safe-auto rule \(ruleID)."
        case .needsConfirmation(let reason): reason
        }
    }

    /// Whether this verdict can ever be offered for quarantine at all. Only
    /// `forbidden` is a hard no — both `safeAuto` and `needsConfirmation`
    /// still require an explicit confirmation sheet in this UI (see
    /// `QuarantineConfirmationSheet`); the difference between them is only
    /// whether a *batch* auto-clean flow may pre-select the item, never
    /// whether confirmation is shown at all.
    var isEligibleForQuarantine: Bool {
        switch self {
        case .forbidden: false
        case .safeAuto, .needsConfirmation: true
        }
    }
}
