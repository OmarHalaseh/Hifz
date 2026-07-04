import Foundation
import SwiftData

/// Centralizes all mutations to memorization progress so views stay declarative.
enum ProgressManager {

    /// Returns the progress row for a unit, creating and inserting one if needed.
    @discardableResult
    static func progress(
        for unit: TrackUnit,
        existing: [MemorizationProgress],
        in context: ModelContext
    ) -> MemorizationProgress {
        if let found = existing.first(where: { $0.unitKey == unit.key }) {
            return found
        }
        let created = MemorizationProgress(from: unit)
        context.insert(created)
        return created
    }

    /// Sets a unit's status, initializing spaced-repetition state on first memorization.
    static func setStatus(
        _ status: MemorizationStatus,
        for progress: MemorizationProgress,
        now: Date = .now
    ) {
        let wasMemorized = progress.status == .memorized
        progress.status = status

        if status == .memorized && !wasMemorized {
            let state = SpacedRepetition.initialState(now: now)
            progress.easeFactor = state.easeFactor
            progress.intervalDays = state.intervalDays
            progress.repetitions = state.repetitions
            progress.dueDate = state.dueDate
            progress.memorizedAt = now
        } else if status != .memorized {
            progress.dueDate = nil
            progress.memorizedAt = nil
        }
    }

    /// Records a review, advances the SM-2 schedule, and logs it.
    static func review(
        _ progress: MemorizationProgress,
        rating: ReviewRating,
        in context: ModelContext,
        now: Date = .now
    ) {
        let state = SRState(
            easeFactor: progress.easeFactor,
            intervalDays: progress.intervalDays,
            repetitions: progress.repetitions,
            dueDate: progress.dueDate,
            lastReviewedAt: progress.lastReviewedAt
        )
        let next = SpacedRepetition.schedule(state, rating: rating, now: now)
        progress.easeFactor = next.easeFactor
        progress.intervalDays = next.intervalDays
        progress.repetitions = next.repetitions
        progress.dueDate = next.dueDate
        progress.lastReviewedAt = next.lastReviewedAt

        // Nudge self-rated strength toward the rating so all modes stay meaningful.
        let target = Double(rating.rawValue) / 3.0
        progress.strength = (progress.strength * 0.6) + (target * 0.4)

        let log = ReviewLog(
            date: now,
            unitKey: progress.unitKey,
            rating: rating,
            intervalAfter: next.intervalDays
        )
        context.insert(log)
    }

    /// The current consecutive-day review streak ending today (or yesterday).
    static func streak(from logs: [ReviewLog], now: Date = .now, calendar: Calendar = .current) -> Int {
        guard !logs.isEmpty else { return 0 }
        let reviewedDays = Set(logs.map { calendar.startOfDay(for: $0.date) })
        var streak = 0
        var day = calendar.startOfDay(for: now)

        // Allow the streak to "hold" if today has no review yet but yesterday did.
        if !reviewedDays.contains(day) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day),
                  reviewedDays.contains(yesterday) else { return 0 }
            day = yesterday
        }

        while reviewedDays.contains(day) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return streak
    }

    /// Deletes all progress and review history.
    static func resetAll(
        progress: [MemorizationProgress],
        logs: [ReviewLog],
        in context: ModelContext
    ) {
        progress.forEach(context.delete)
        logs.forEach(context.delete)
    }
}
