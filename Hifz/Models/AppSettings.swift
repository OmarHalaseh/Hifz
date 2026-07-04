import Foundation
import SwiftData

/// Single-row user preferences.
@Model
final class AppSettings {
    var granularity: Granularity
    var revisionMode: RevisionMode

    // Revision reminder (existing).
    var remindersEnabled: Bool
    var reminderHour: Int
    var reminderMinute: Int

    /// Target number of reviews to complete each day.
    var dailyGoal: Int

    /// Target number of *new* ayahs to memorize each day — drives the forecast.
    var dailyNewAyahs: Int = 3

    /// Whether the user has been through the initial goal-setup prompt.
    var hasSetGoal: Bool = false

    // Memorization reminder (nudge to learn new ayahs).
    var memorizeReminderEnabled: Bool = false
    var memorizeReminderHour: Int = 7
    var memorizeReminderMinute: Int = 0

    init(
        granularity: Granularity = .surah,
        revisionMode: RevisionMode = .spacedRepetition,
        remindersEnabled: Bool = false,
        reminderHour: Int = 20,
        reminderMinute: Int = 0,
        dailyGoal: Int = 5,
        dailyNewAyahs: Int = 3,
        hasSetGoal: Bool = false,
        memorizeReminderEnabled: Bool = false,
        memorizeReminderHour: Int = 7,
        memorizeReminderMinute: Int = 0
    ) {
        self.granularity = granularity
        self.revisionMode = revisionMode
        self.remindersEnabled = remindersEnabled
        self.reminderHour = reminderHour
        self.reminderMinute = reminderMinute
        self.dailyGoal = dailyGoal
        self.dailyNewAyahs = dailyNewAyahs
        self.hasSetGoal = hasSetGoal
        self.memorizeReminderEnabled = memorizeReminderEnabled
        self.memorizeReminderHour = memorizeReminderHour
        self.memorizeReminderMinute = memorizeReminderMinute
    }

    /// Fetches the single settings row, creating it on first launch.
    static func current(in context: ModelContext) -> AppSettings {
        let descriptor = FetchDescriptor<AppSettings>()
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let settings = AppSettings()
        context.insert(settings)
        return settings
    }
}
