import Foundation

/// The mutable scheduling state SM-2 operates on.
struct SRState {
    var easeFactor: Double
    var intervalDays: Int
    var repetitions: Int
    var dueDate: Date?
    var lastReviewedAt: Date?
}

/// The classic SM-2 spaced-repetition algorithm, with a gentler `Hard`.
///
/// What each rating does to the interval:
///
/// - **Again** — a lapse. The interval restarts at a single day and
///   `repetitions` returns to 0; the (now lower) ease factor is kept.
/// - **Hard** — recalled, but with difficulty. This is still a pass: the
///   interval creeps forward by `hardIntervalMultiplier` rather than by the
///   ease factor, and `repetitions` advances as on any pass. It never shrinks
///   and never resets — a page you struggled through comes back soon, without
///   being thrown all the way back to day one.
/// - **Good** / **Easy** — a clean pass: 1 → 6 → ×ease days.
///
/// Every rating then applies the standard SM-2 ease update, which is what makes
/// `Hard` lower the ease factor and so slow every later interval too. Ease is
/// clamped to a floor of 1.3.
enum SpacedRepetition {
    static let minimumEase = 1.3

    /// How far a `Hard` rating stretches the interval, rounded up. Deliberately
    /// far below the ease factor (never under 1.3): difficult recall should
    /// barely gain ground. Short intervals grow by less than a day at this rate,
    /// so `schedule` floors the result at one more day than before — `Hard`
    /// always moves forward, if only just.
    static let hardIntervalMultiplier = 1.2

    static func schedule(
        _ state: SRState,
        rating: ReviewRating,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> SRState {
        var s = state
        let quality = rating.quality   // 1, 3, 4, or 5

        switch rating {
        case .again:
            // Lapsed — restart the interval but keep a (reduced) ease factor.
            s.repetitions = 0
            s.intervalDays = 1
        case .hard:
            // A pass, so the interval grows and `repetitions` advances — but by
            // the flat hard multiplier instead of the ease factor, and by at
            // least a day so it can never stall or shrink.
            let stretched = Int((Double(s.intervalDays) * hardIntervalMultiplier).rounded(.up))
            s.intervalDays = max(s.intervalDays + 1, stretched, 1)
            s.repetitions += 1
        case .good, .easy:
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
