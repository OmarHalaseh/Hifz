import Foundation

/// The ḥifẓ plan: *which surah is learned when*, and *what is revised on which
/// day*. Both are projections from today's state — nothing here is stored, so the
/// plan simply re-forms when the user learns faster, slower, or changes settings.
///
/// Pure logic (no SwiftData / UI), unit-testable with plain values.
enum HifzPlan {

    // MARK: - New lessons (Sabaq)

    /// One surah's slot in the learning schedule. `firstAyah > 1` means the surah
    /// is already partly memorized and the plan picks up where it left off.
    struct SurahLesson: Identifiable, Hashable {
        let surah: Int
        let firstAyah: Int
        let lastAyah: Int
        let startDay: Int       // 0 = the plan's first day
        let endDay: Int
        let start: Date
        let end: Date

        var id: Int { surah }
        var days: Int { endDay - startDay + 1 }
    }

    /// Lays out the still-unlearned ayahs (already in learning order) as one Sabaq
    /// portion per day, starting on `start`, using the same line-measured portion
    /// rule as the real lesson (`HifzProgram.nextSabaqAtoms(…lines:…)`): an ayah
    /// joins a day while it brings the day nearer to `lines` than stopping would.
    /// A day's portion can run across a surah boundary, exactly as a real lesson can.
    static func sabaqSchedule(
        unlearned: [(surah: Int, ayah: Int)],
        lines: Int,
        start: Date,
        lineCost: (Int, Int) -> Double = { MushafLayout.lineCost(surah: $0, ayah: $1) },
        calendar: Calendar = .current
    ) -> [SurahLesson] {
        let target = Double(max(1, lines))
        let day0 = calendar.startOfDay(for: start)
        func date(_ d: Int) -> Date { calendar.date(byAdding: .day, value: d, to: day0) ?? day0 }

        var out: [SurahLesson] = []
        var day = 0, total = 0.0, inDay = 0
        var current: (surah: Int, first: Int, last: Int, startDay: Int, endDay: Int)?

        func flush() {
            guard let c = current else { return }
            out.append(SurahLesson(surah: c.surah, firstAyah: c.first, lastAyah: c.last,
                                   startDay: c.startDay, endDay: c.endDay,
                                   start: date(c.startDay), end: date(c.endDay)))
        }

        for atom in unlearned {
            let cost = max(0, lineCost(atom.surah, atom.ayah))
            if inDay > 0, total + cost / 2 > target {
                day += 1; total = 0; inDay = 0
            }
            total += cost; inDay += 1
            if let c = current, c.surah == atom.surah {
                current = (c.surah, c.first, atom.ayah, c.startDay, day)
            } else {
                flush()
                current = (atom.surah, atom.ayah, atom.ayah, day, day)
            }
        }
        flush()
        return out
    }

    // MARK: - Revision (Manzil)

    /// The Manzil blocks the scheduler will put on one day.
    struct RevisionDay: Identifiable, Hashable {
        let date: Date
        let blocks: [HifzPageScheduler.RevisionBlock]

        var id: Date { date }
        var lines: Double { blocks.reduce(0) { $0 + $1.lines } }
    }

    /// Projects the Manzil queue over the next `days` days, assuming each day's
    /// revision is done and recited well (a `good` review per ayah). Ayahs still
    /// in their Sabqi week join Manzil on the day they age out, as they would for
    /// real. New lessons learned in the meantime aren't foreseen.
    static func revisionForecast(
        ayahs: [HifzPageScheduler.AyahSnapshot],
        days: Int,
        now: Date = .now,
        fromEnd: Bool = false,
        lineCost: @escaping (Int, Int) -> Double = { MushafLayout.lineCost(surah: $0, ayah: $1) },
        calendar: Calendar = .current
    ) -> [RevisionDay] {
        var state = Dictionary(ayahs.filter { $0.memorizedAt != nil }.map { ($0.key, $0) },
                               uniquingKeysWith: { a, _ in a })
        let today = calendar.startOfDay(for: now)
        var out: [RevisionDay] = []

        for d in 0..<max(0, days) {
            guard let date = calendar.date(byAdding: .day, value: d, to: today) else { break }
            let blocks = HifzPageScheduler.revisionBlocks(
                from: Array(state.values), lineCost: lineCost, now: date, calendar: calendar
            )
            let queue = HifzPageScheduler.blockQueue(
                blocks, lineBudget: HifzPageScheduler.blockLineBudget(blocks),
                now: date, fromEnd: fromEnd, calendar: calendar
            )
            out.append(RevisionDay(date: date, blocks: queue))

            // Advance every reviewed ayah one SM-2 step, as a real session would.
            for key in queue.flatMap(\.ayahKeys) {
                guard var a = state[key] else { continue }
                let next = SpacedRepetition.schedule(
                    SRState(easeFactor: a.easeFactor, intervalDays: a.intervalDays,
                            repetitions: a.repetitions, dueDate: nil, lastReviewedAt: a.lastReviewedAt),
                    rating: .good, now: date, calendar: calendar
                )
                a.easeFactor = next.easeFactor
                a.intervalDays = next.intervalDays
                a.repetitions = next.repetitions
                a.lastReviewedAt = next.lastReviewedAt
                state[key] = a
            }
        }
        return out
    }
}
