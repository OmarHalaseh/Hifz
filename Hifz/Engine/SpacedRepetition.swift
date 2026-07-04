import Foundation

/// The mutable scheduling state SM-2 operates on.
struct SRState {
    var easeFactor: Double
    var intervalDays: Int
    var repetitions: Int
    var dueDate: Date?
    var lastReviewedAt: Date?
}

/// The classic SM-2 spaced-repetition algorithm.
///
/// On a successful recall the interval grows 1 → 6 → ×ease days; a failure
/// (`Again`/`Hard` below the quality threshold) resets it to a single day.
/// Ease factor is clamped to a floor of 1.3.
enum SpacedRepetition {
    static let minimumEase = 1.3

    static func schedule(
        _ state: SRState,
        rating: ReviewRating,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> SRState {
        var s = state
        let quality = rating.quality   // 1, 3, 4, or 5

        if quality < 3 {
            // Lapsed — restart the interval but keep a (reduced) ease factor.
            s.repetitions = 0
            s.intervalDays = 1
        } else {
            switch s.repetitions {
            case 0: s.intervalDays = 1
            case 1: s.intervalDays = 6
            default: s.intervalDays = Int((Double(s.intervalDays) * s.easeFactor).rounded())
            }
            s.repetitions += 1
        }

        // Standard SM-2 ease update.
        let q = Double(quality)
        let updatedEase = s.easeFactor + (0.1 - (5 - q) * (0.08 + (5 - q) * 0.02))
        s.easeFactor = max(minimumEase, updatedEase)

        s.lastReviewedAt = now
        let startOfToday = calendar.startOfDay(for: now)
        s.dueDate = calendar.date(byAdding: .day, value: s.intervalDays, to: startOfToday)
        return s
    }

    /// Initial state for a unit that has just been marked memorized:
    /// due today so it enters the queue for a first confirming review.
    static func initialState(now: Date = .now, calendar: Calendar = .current) -> SRState {
        SRState(
            easeFactor: 2.5,
            intervalDays: 0,
            repetitions: 0,
            dueDate: calendar.startOfDay(for: now),
            lastReviewedAt: nil
        )
    }
}
