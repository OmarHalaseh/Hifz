import Foundation

/// Decides which memorized units need revising, ordered by priority,
/// according to the user's chosen `RevisionMode`.
enum RevisionScheduler {
    /// Units that are due / most in need of revision, highest priority first.
    static func dueItems(
        _ items: [MemorizationProgress],
        mode: RevisionMode,
        granularity: Granularity,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [MemorizationProgress] {
        let memorized = items.filter { $0.status == .memorized && $0.granularity == granularity }
        switch mode {
        case .spacedRepetition:
            let endOfToday = calendar.startOfDay(for: now)
            return memorized
                .filter { ($0.dueDate ?? .distantPast) <= endOfToday }
                .sorted { ($0.dueDate ?? .distantPast) < ($1.dueDate ?? .distantPast) }
        case .lastReviewed:
            return memorized
                .sorted { ($0.lastReviewedAt ?? .distantPast) < ($1.lastReviewedAt ?? .distantPast) }
        case .selfRated:
            return memorized.sorted { $0.strength < $1.strength }
        }
    }

    /// Count due specifically for spaced repetition (used on the dashboard badge).
    static func dueCount(
        _ items: [MemorizationProgress],
        mode: RevisionMode,
        granularity: Granularity,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Int {
        dueItems(items, mode: mode, granularity: granularity, now: now, calendar: calendar).count
    }
}
