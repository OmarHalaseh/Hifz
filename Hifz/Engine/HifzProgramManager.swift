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
        manuallyMemorizedKeys: Set<String> = [],
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

        let picked = sabaqPortionAtoms(
            existing: existing, manuallyMemorizedKeys: manuallyMemorizedKeys,
            settings: settings, recentAccuracy: recentAccuracy, fromEnd: fromEnd
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

    /// Today's Sabaq portion as plain atoms — creates no rows and writes no state.
    /// Shared by `ensureTodaysSabaq` and the home screen's preview, so the size
    /// shown before you tap matches the lesson you actually get.
    static func sabaqPortionAtoms(
        existing: [HifzAyah],
        manuallyMemorizedKeys: Set<String> = [],
        settings: AppSettings,
        recentAccuracy: Double,
        fromEnd: Bool = false
    ) -> [(surah: Int, ayah: Int, page: Int, juz: Int)] {
        // Size the portion around the user's chosen daily-lesson unit, then take
        // that many *printed lines* of the next unlearned material.
        let lines = HifzProgram.portionLines(
            baseLines: settings.sabaqUnit.baseLines, recentAccuracy: recentAccuracy
        )
        // "Already done" for Sabaq = memorized/in-progress program rows *plus* any
        // ayahs the user marked memorized elsewhere (surah-list bulk mark, page
        // tracking). Without the manual keys, list-marked surahs have no HifzAyah
        // rows and get re-offered as brand-new lessons.
        var taken = Set(existing.filter { $0.isMemorized || $0.phase == .sabaq }.map(\.key))
        taken.formUnion(manuallyMemorizedKeys)
        return HifzProgram.nextSabaqAtoms(
            orderedAtoms: HifzText.orderedAtomTuples,
            memorizedOrInProgressKeys: taken, lines: lines, fromEnd: fromEnd
        )
    }

    // MARK: - Seeding pre-existing ḥifẓ

    /// How many days back a bulk-marked ayah's `memorizedAt` is dated: one day past
    /// the Sabqi window, so established ḥifẓ lands straight in the Manzil long-term
    /// rotation instead of this week's daily-recitation (Sabqi) set.
    static let seedBackdateDays = HifzPageScheduler.sabqiDays + 1

    /// Creates memorized `HifzAyah` rows for every ayah in `units` — the bridge for
    /// marking pre-existing ḥifẓ memorized outside the guided Sabaq flow (e.g. the
    /// surah-list bulk mark). Without these rows the scheduler can't see the surah, so
    /// it neither revises it (Manzil) nor counts it drilled.
    ///
    /// Rows are dated just outside the Sabqi window so they enter Manzil directly, and
    /// are due immediately — the 30-day line budget spreads them across the cycle.
    /// Idempotent and non-destructive: any ayah that already has a `HifzAyah` row
    /// (in Sabaq, or genuinely memorized with real review history) is left untouched.
    @discardableResult
    static func seedMemorized(
        units: [TrackUnit],
        existing: [HifzAyah],
        in context: ModelContext,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [HifzAyah] {
        let wanted = Set(units.flatMap { MemorizationCoverage.ayahKeys(in: $0) })
        guard !wanted.isEmpty else { return [] }
        let established = calendar.date(
            byAdding: .day, value: -seedBackdateDays, to: calendar.startOfDay(for: now)
        ) ?? now

        var have = Set(existing.map(\.key))
        var created: [HifzAyah] = []
        for atom in HifzText.orderedAtomTuples {
            let key = HifzAyah.makeKey(surah: atom.surah, ayah: atom.ayah)
            guard wanted.contains(key), !have.contains(key) else { continue }
            have.insert(key)
            let row = HifzAyah(surah: atom.surah, ayah: atom.ayah, page: atom.page,
                               juz: atom.juz, phase: .manzil)
            row.memorizedAt = established
            context.insert(row)
            created.append(row)
        }
        return created
    }

    /// The "quality over speed" gate: mark an ayah memorized only on a flawless
    /// recall. Sets `memorizedAt` once, graduates it to Sabqi, and — because a
    /// flawless recall *is* the first successful review — advances SM-2 one step
    /// so the ayah is stamped reviewed-today and its next Sabqi review is
    /// scheduled in the future (tomorrow), not re-listed as due the same day.
    static func confirmFlawless(
        _ ayah: HifzAyah,
        state: HifzProgramState,
        in context: ModelContext,
        now: Date = .now
    ) {
        guard !ayah.isMemorized else { return }
        ayah.memorizedAt = now
        ayah.phase = .sabqi
        let first = SpacedRepetition.schedule(SpacedRepetition.initialState(now: now),
                                              rating: .good, now: now)
        ayah.easeFactor = first.easeFactor
        ayah.intervalDays = first.intervalDays      // 1
        ayah.repetitions = first.repetitions        // 1
        ayah.dueDate = first.dueDate                // tomorrow
        ayah.lastReviewedAt = first.lastReviewedAt  // now — completed today
        // A flawless first recall *is* a completed review, so log it like one.
        // Without this a day spent only on a new lesson leaves no `ReviewLog` and
        // therefore doesn't count toward the streak, statistics or heatmap.
        context.insert(ReviewLog(date: now, unitKey: ayah.key, rating: .good,
                                 intervalAfter: first.intervalDays))
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
    /// Built once — all 6236 atoms, now read on every Sabaq preview as well as on
    /// assignment, so remapping them per call would be wasteful.
    static let orderedAtomTuples: [(surah: Int, ayah: Int, page: Int, juz: Int)] =
        QuranText.orderedAtoms.map { (surah: $0.surah, ayah: $0.ayah.n, page: $0.ayah.page, juz: $0.ayah.juz) }
}
