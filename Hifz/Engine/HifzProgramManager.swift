import Foundation
import SwiftData

/// Applies `HifzProgram` decisions to the SwiftData store. Centralizes every
/// mutation so views stay declarative (mirrors `ProgressManager`).
enum HifzProgramManager {

    // MARK: - Sabaq assignment

    /// Ensures a Sabaq portion is assigned for today, creating the `HifzAyah`
    /// rows for it, and returns them. Re-assigning on the same day is a no-op.
    @discardableResult
    static func ensureTodaysSabaq(
        state: HifzProgramState,
        existing: [HifzAyah],
        settings: AppSettings,
        recentAccuracy: Double,
        fromEnd: Bool = false,
        in context: ModelContext,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [HifzAyah] {
        let today = calendar.startOfDay(for: now)

        // Already assigned today → return the current portion.
        if let assigned = state.sabaqAssignedOn, calendar.isDate(assigned, inSameDayAs: today),
           !state.sabaqKeys.isEmpty {
            return state.sabaqKeys.compactMap { key in existing.first { $0.key == key } }
        }

        // Size the portion around the user's chosen daily-lesson unit, then pick
        // the next unmemorized ayahs.
        let lines = HifzProgram.portionLines(
            baseLines: settings.sabaqUnit.baseLines, recentAccuracy: recentAccuracy
        )
        let count = HifzProgram.ayahCount(forLines: lines)
        let taken = Set(existing.filter { $0.isMemorized || $0.phase == .sabaq }.map(\.key))
        let atoms = HifzText.orderedAtomTuples
        let picked = HifzProgram.nextSabaqAtoms(
            orderedAtoms: atoms, memorizedOrInProgressKeys: taken, count: count, fromEnd: fromEnd
        )

        var rows: [HifzAyah] = []
        for atom in picked {
            let key = HifzAyah.makeKey(surah: atom.surah, ayah: atom.ayah)
            if let found = existing.first(where: { $0.key == key }) {
                rows.append(found)
            } else {
                let row = HifzAyah(surah: atom.surah, ayah: atom.ayah, page: atom.page, juz: atom.juz)
                context.insert(row)
                rows.append(row)
            }
        }

        state.sabaqAssignedOn = today
        state.sabaqKeys = rows.map(\.key)
        state.sabaqConfirmedKeys = []
        return rows
    }

    /// The "quality over speed" gate: mark an ayah memorized only on a flawless
    /// recall. Sets `memorizedAt` once, graduates it to Sabqi, and seeds SM-2.
    static func confirmFlawless(
        _ ayah: HifzAyah,
        state: HifzProgramState,
        now: Date = .now
    ) {
        guard !ayah.isMemorized else { return }
        ayah.memorizedAt = now
        ayah.phase = .sabqi
        let sr = SpacedRepetition.initialState(now: now)
        ayah.easeFactor = sr.easeFactor
        ayah.intervalDays = sr.intervalDays
        ayah.repetitions = sr.repetitions
        ayah.dueDate = sr.dueDate
        if !state.sabaqConfirmedKeys.contains(ayah.key) {
            state.sabaqConfirmedKeys.append(ayah.key)
        }
    }

    // MARK: - Sabqi

    /// Records that today's Sabqi was fully recited, unlocking new Sabaq.
    static func clearSabqi(state: HifzProgramState, now: Date = .now, calendar: Calendar = .current) {
        state.sabqiClearedOn = calendar.startOfDay(for: now)
    }

    // MARK: - Reviews & mistakes

    /// A correct recall in Sabqi/Manzil: advance SM-2, promote Sabqi→Manzil once
    /// it ages past the 7-day window, and log it.
    static func recordCorrect(
        _ ayah: HifzAyah,
        rating: ReviewRating = .good,
        in context: ModelContext,
        now: Date = .now,
        calendar: Calendar = .current
    ) {
        let state = SRState(
            easeFactor: ayah.easeFactor,
            intervalDays: ayah.intervalDays,
            repetitions: ayah.repetitions,
            dueDate: ayah.dueDate,
            lastReviewedAt: ayah.lastReviewedAt
        )
        let next = SpacedRepetition.schedule(state, rating: rating, now: now)
        ayah.easeFactor = next.easeFactor
        ayah.intervalDays = next.intervalDays
        ayah.repetitions = next.repetitions
        ayah.dueDate = next.dueDate
        ayah.lastReviewedAt = next.lastReviewedAt

        // Age out of the recent-revision window into the long-term cycle.
        if ayah.phase == .sabqi, let m = ayah.memorizedAt,
           let cutoff = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: now)),
           m < cutoff {
            ayah.phase = .manzil
        }

        context.insert(ReviewLog(date: now, unitKey: ayah.key, rating: rating, intervalAfter: next.intervalDays))
    }

    /// A mistake at this ayah: log it, bump the weak-link counter, halve the SM-2
    /// interval so it resurfaces sooner, and (in Sabqi) it stays due.
    static func recordMistake(
        _ ayah: HifzAyah,
        kind: String = "slip",
        in context: ModelContext,
        now: Date = .now,
        calendar: Calendar = .current
    ) {
        context.insert(MistakeLog(date: now, ayahKey: ayah.key, kind: kind))
        ayah.mistakeCount += 1
        ayah.intervalDays = max(1, ayah.intervalDays / 2)
        ayah.repetitions = 0
        ayah.lastReviewedAt = now
        ayah.dueDate = calendar.startOfDay(for: now)   // due again today
    }

    // MARK: - Cursor

    static func advanceManzilCursor(state: HifzProgramState, memorizedPageCount: Int) {
        state.manzilCursor = HifzProgram.advanceCursor(
            cursor: state.manzilCursor, memorizedPageCount: memorizedPageCount
        )
    }

    /// Recent recall accuracy from the last `window` days of mistakes vs reviews.
    static func recentAccuracy(
        reviews: [ReviewLog],
        mistakes: [MistakeLog],
        now: Date = .now,
        window: Int = 7,
        calendar: Calendar = .current
    ) -> Double {
        guard let cutoff = calendar.date(byAdding: .day, value: -window, to: now) else { return 1 }
        let r = reviews.filter { $0.date >= cutoff }.count
        let m = mistakes.filter { $0.date >= cutoff }.count
        return HifzProgram.recentAccuracy(reviews: r + m, mistakes: m)
    }
}

/// Bridges the bundled Quran asset into the plain tuples `HifzProgram` expects.
enum HifzText {
    static var orderedAtomTuples: [(surah: Int, ayah: Int, page: Int, juz: Int)] {
        QuranText.orderedAtoms.map { (surah: $0.surah, ayah: $0.ayah.n, page: $0.ayah.page, juz: $0.ayah.juz) }
    }
}
