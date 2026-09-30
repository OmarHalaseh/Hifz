import Foundation

/// A projection of how a user's memorization is tracking toward the next
/// juz milestone and toward completing the whole Quran.
///
/// Everything is expressed in **ayahs** so the forecast is comparable across
/// granularities: the whole Quran is `QuranData.totalAyahs` (6236) and a juz is
/// treated as an equal `1/30` slice of that total.
struct MemorizationForecast {
    let totalAyahs: Int
    let memorizedAyahs: Int

    /// The user's chosen daily memorization pace (new ayahs/day), floored at 1.
    let goalPerDay: Int
    /// Ayahs/day actually memorized recently (last 30 days). 0 if no recent activity.
    let recentPacePerDay: Double

    /// The next juz the user will complete, or `nil` once the Quran is finished.
    let nextJuz: Int?
    let ayahsToNextJuz: Int

    let reference: Date

    var remainingAyahs: Int { max(0, totalAyahs - memorizedAyahs) }
    var isComplete: Bool { remainingAyahs == 0 }

    var fraction: Double {
        totalAyahs == 0 ? 0 : Double(memorizedAyahs) / Double(totalAyahs)
    }

    /// Number of juz fully memorized so far (0…30).
    var completedJuz: Int {
        Int((Double(memorizedAyahs) / juzSize).rounded(.down))
    }

    private var juzSize: Double { Double(totalAyahs) / Double(QuranData.totalJuz) }

    // MARK: - Whole-Quran forecast

    /// Days to finish the whole Quran at the goal pace (`nil` if already done).
    var daysToFinishAtGoal: Int? { days(forAyahs: remainingAyahs, pace: Double(goalPerDay)) }
    var finishDateAtGoal: Date? { date(afterDays: daysToFinishAtGoal) }

    /// Days to finish at the recent actual pace (`nil` if done or no recent activity).
    var daysToFinishAtRecentPace: Int? {
        recentPacePerDay > 0 ? days(forAyahs: remainingAyahs, pace: recentPacePerDay) : nil
    }
    var finishDateAtRecentPace: Date? { date(afterDays: daysToFinishAtRecentPace) }

    // MARK: - Next-milestone forecast

    /// Days to reach the next juz milestone at the goal pace.
    var daysToNextJuz: Int? { days(forAyahs: ayahsToNextJuz, pace: Double(goalPerDay)) }
    var nextJuzDate: Date? { date(afterDays: daysToNextJuz) }

    // MARK: - Helpers

    private func days(forAyahs ayahs: Int, pace: Double) -> Int? {
        guard ayahs > 0 else { return 0 }
        guard pace > 0 else { return nil }
        return Int((Double(ayahs) / pace).rounded(.up))
    }

    private func date(afterDays days: Int?) -> Date? {
        guard let days else { return nil }
        return Calendar.current.date(byAdding: .day, value: days, to: reference)
    }
}

extension MemorizationForecast {

    /// Builds a forecast from everything the user has memorized, by either route.
    ///
    /// Counts **distinct ayahs** across both tracks — the ayah-atomic program
    /// (`HifzAyah`) and every manually marked unit, whatever granularity it was
    /// marked at — the same union the dashboard ring shows. So Sabaq progress
    /// moves the goal bar, switching tracking granularity never hides progress,
    /// and overlapping units are not counted twice. `recentWindow` bounds the
    /// pace estimate.
    static func compute(
        program: [HifzAyah] = [],
        progress: [MemorizationProgress],
        settings: AppSettings,
        now: Date = .now,
        calendar: Calendar = .current,
        recentWindow: Int = 30
    ) -> MemorizationForecast {
        let total = QuranData.totalAyahs
        let memorizedKeys = MemorizationCoverage.memorizedAyahKeys(program: program, progress: progress)
        let memorizedAyahs = min(total, memorizedKeys.count)

        // Recent pace: ayahs learned within the window / elapsed days in the window.
        let pace = recentPace(
            dates: MemorizationCoverage.memorizationDates(program: program, progress: progress),
            now: now, calendar: calendar, window: recentWindow
        )

        // Next-juz milestone (even 1/30 slices of the total).
        let juzSize = Double(total) / Double(QuranData.totalJuz)
        let completedJuz = Int((Double(memorizedAyahs) / juzSize).rounded(.down))
        let nextJuz: Int?
        let ayahsToNextJuz: Int
        if memorizedAyahs >= total {
            nextJuz = nil
            ayahsToNextJuz = 0
        } else {
            let target = min(QuranData.totalJuz, completedJuz + 1)
            nextJuz = target
            let threshold = Int((Double(target) * juzSize).rounded())
            ayahsToNextJuz = max(1, threshold - memorizedAyahs)
        }

        return MemorizationForecast(
            totalAyahs: total,
            memorizedAyahs: memorizedAyahs,
            goalPerDay: max(1, settings.dailyNewAyahs),
            recentPacePerDay: pace,
            nextJuz: nextJuz,
            ayahsToNextJuz: ayahsToNextJuz,
            reference: now
        )
    }

    private static func recentPace(
        dates: [String: Date],
        now: Date,
        calendar: Calendar,
        window: Int
    ) -> Double {
        guard let cutoff = calendar.date(byAdding: .day, value: -window, to: now) else { return 0 }
        let recent = dates.values.filter { $0 >= cutoff }
        guard let firstDate = recent.min() else { return 0 }

        // Divide by the elapsed span since the first recent memorization (capped to
        // the window) so early users aren't penalized for a short history.
        let start = max(firstDate, cutoff)
        let elapsedDays = calendar.dateComponents([.day], from: start, to: now).day ?? 0
        let denominator = Double(min(window, max(1, elapsedDays)))
        return Double(recent.count) / denominator
    }
}
