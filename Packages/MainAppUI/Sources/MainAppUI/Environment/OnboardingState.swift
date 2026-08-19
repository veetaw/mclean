import Foundation

/// Tiny persisted flag for "has this user already been through the
/// onboarding flow." Deliberately not part of `AppEnvironment` (it's pure
/// UI-launch-sequencing state, not a backend), and deliberately not gating
/// app launch itself — `ContentView` shows the onboarding sheet *over* a
/// fully usable window, never blocks it from appearing.
public enum OnboardingState {
    private static let defaultsKey = "pro.mclean.onboarding.completed"

    public static func hasCompletedOnboarding(userDefaults: UserDefaults = .standard) -> Bool {
        userDefaults.bool(forKey: defaultsKey)
    }

    public static func markOnboardingCompleted(userDefaults: UserDefaults = .standard) {
        userDefaults.set(true, forKey: defaultsKey)
    }

    /// Test/debug hook — resets the flag so onboarding shows again.
    public static func reset(userDefaults: UserDefaults = .standard) {
        userDefaults.removeObject(forKey: defaultsKey)
    }
}
