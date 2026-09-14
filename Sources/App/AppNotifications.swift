import Foundation
import UserNotifications

/// Thin wrapper around `UNUserNotificationCenter` for the break reminder.
///
/// Kept in the app layer (not Core) because it imports `UserNotifications`,
/// which the Core module deliberately avoids. The view model only ever calls
/// the injected `postReminder` / `requestAuthorization` closures, so the
/// platform detail stays here.
enum AppNotifications {
    /// Ask for permission to post notifications. Safe to call repeatedly.
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
            // No action needed on either outcome; the reminder simply will or
            // will not be able to post.
        }
    }

    /// Post a break-reminder notification naming the running task.
    static func postBreakReminder(taskTitle: String) {
        let content = UNMutableNotificationContent()
        content.title = "Time for a break"
        content.body = "You've been on \"\(taskTitle)\" for an hour. Stand up and stretch."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "timetracker.break-reminder",
            content: content,
            trigger: nil // deliver now
        )
        UNUserNotificationCenter.current().add(request) { _ in }
    }
}
