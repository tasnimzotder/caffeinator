import Foundation
import UserNotifications

/// Manages local notifications for the application
class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()
    
    @Published var isAuthorized = false
    
    private override init() {
        super.init()
        checkAuthorization()
    }
    
    // MARK: - Authorization
    
    /// Request notification permission from the user
    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, error in
            DispatchQueue.main.async {
                self?.isAuthorized = granted
            }
            
            if let error = error {
                print("Notification permission error: \(error.localizedDescription)")
            }
        }
    }
    
    /// Check current authorization status
    func checkAuthorization() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                self?.isAuthorized = settings.authorizationStatus == .authorized
            }
        }
    }
    
    // MARK: - Send Notifications
    
    /// Send a notification
    func sendNotification(title: String, body: String, identifier: String = UUID().uuidString) {
        guard isAuthorized else {
            print("Notifications not authorized")
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil // Deliver immediately
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to send notification: \(error.localizedDescription)")
            }
        }
    }
    
    /// Notify that caffeinate timer has expired
    func notifyCaffeinateExpired() {
        sendNotification(
            title: "Caffeinator",
            body: "Timer expired. Your Mac is no longer being kept awake.",
            identifier: "caffeinate-expired"
        )
    }
    
    /// Notify that a watched process has ended
    func notifyWatchedProcessEnded(processName: String) {
        sendNotification(
            title: "Caffeinator",
            body: "\(processName) has ended. Your Mac is no longer being kept awake.",
            identifier: "process-ended"
        )
    }
    
    /// Notify that caffeinate has been activated
    func notifyCaffeinateActivated(duration: String?) {
        let body: String
        if let duration = duration {
            body = "Keeping your Mac awake for \(duration)"
        } else {
            body = "Keeping your Mac awake indefinitely"
        }
        
        sendNotification(
            title: "Caffeinator Activated",
            body: body,
            identifier: "caffeinate-activated"
        )
    }
    
    // MARK: - Clear Notifications
    
    /// Remove all pending notifications
    func clearPendingNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
    
    /// Remove all delivered notifications
    func clearDeliveredNotifications() {
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }
}
