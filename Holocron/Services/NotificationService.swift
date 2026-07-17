import Foundation
import UserNotifications

/// macOS user notifications for moments when the notch is not visible
/// (external-display-only setups, panel hidden). Optional — refusal is fine.
final class NotificationService {
    private var authorized = false

    func requestAuthorizationIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { [weak self] notificationSettings in
            switch notificationSettings.authorizationStatus {
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    self?.authorized = granted
                }
            case .authorized, .provisional:
                self?.authorized = true
            default:
                self?.authorized = false
            }
        }
    }

    func post(title: String, body: String, identifier: String = UUID().uuidString) {
        guard authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
