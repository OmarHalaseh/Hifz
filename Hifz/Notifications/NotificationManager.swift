import Foundation
import UserNotifications

/// Manages the daily "time to revise" and "time to memorize" reminders.
@MainActor
final class NotificationManager {
    static let shared = NotificationManager()
    private let center = UNUserNotificationCenter.current()
    private let reminderID = "hifz.daily.revision"
    private let memorizeID = "hifz.daily.memorize"

    private init() {}

    /// Prompts for permission. Returns whether notifications are authorized.
    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    /// Schedules (or cancels) the daily reminder at the given time.
    func updateDailyReminder(enabled: Bool, hour: Int, minute: Int) async {
        center.removePendingNotificationRequests(withIdentifiers: [reminderID])
        guard enabled else { return }

        let granted = await requestAuthorization()
        guard granted else { return }

        let content = UNMutableNotificationContent()
        content.title = "Time to revise"
        content.body = "Keep your hifz strong — a few surahs are waiting for review."
        content.sound = .default

        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

        let request = UNNotificationRequest(identifier: reminderID, content: content, trigger: trigger)
        try? await center.add(request)
    }

    /// Schedules (or cancels) the daily "memorize new ayahs" reminder.
    func updateMemorizationReminder(enabled: Bool, hour: Int, minute: Int, dailyAyahs: Int) async {
        center.removePendingNotificationRequests(withIdentifiers: [memorizeID])
        guard enabled else { return }

        let granted = await requestAuthorization()
        guard granted else { return }

        let content = UNMutableNotificationContent()
        content.title = "Time to memorize"
        let ayahWord = dailyAyahs == 1 ? "ayah" : "ayahs"
        content.body = "Learn \(dailyAyahs) new \(ayahWord) today to stay on track for your goal."
        content.sound = .default

        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

        let request = UNNotificationRequest(identifier: memorizeID, content: content, trigger: trigger)
        try? await center.add(request)
    }
}
