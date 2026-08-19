import Foundation
import UserNotifications

/// Abstraction over posting a local user notification, so threshold/cooldown
/// logic can be tested by recording calls instead of touching the real
/// notification center -- which also requires user-granted authorization
/// this package cannot assume it has.
public protocol NotificationPosting: Sendable {
    func post(identifier: String, title: String, body: String) async
}

/// Real implementation, backed by `UNUserNotificationCenter`. Degrades
/// gracefully: if authorization hasn't been granted, the notification is
/// silently skipped rather than crashing or throwing -- this package cannot
/// assume it owns the app's notification-permission prompt, and observing +
/// notifying is always allowed to be a no-op, never a hard failure.
public struct UserNotificationCenterPoster: NotificationPosting {
    public init() {}

    public func post(identifier: String, title: String, body: String) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        try? await center.add(request)
    }
}
