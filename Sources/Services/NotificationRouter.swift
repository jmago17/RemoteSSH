import Foundation
import UserNotifications

/// Owns local-notification permission, foreground presentation, and routing a
/// notification tap to "open this session". Bridges ntfy messages into iOS
/// notifications.
@MainActor
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    /// Called when the user taps a notification (or opens a deep link).
    var onOpenSession: ((String) -> Void)?

    func configure() {
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Posts a local notification for a session that needs attention.
    func postAttention(session: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = "\(session) needs attention"
        content.body = body
        content.sound = .default
        content.userInfo = ["session": session]

        let request = UNNotificationRequest(
            identifier: "attention-\(session)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: UNUserNotificationCenterDelegate

    // Show banners even when the app is in the foreground.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    // Handle taps: jump to the session.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let session = response.notification.request.content.userInfo["session"] as? String
        if let session {
            Task { @MainActor in self.onOpenSession?(session) }
        }
        completionHandler()
    }
}
