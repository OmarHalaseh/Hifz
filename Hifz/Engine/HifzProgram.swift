import Foundation

/// Pure decision logic for the Sabaq / Sabqi / Manzil ḥifẓ program. No SwiftData
/// or UI here so it can be unit-tested directly; `HifzProgramManager` applies the
/// results to the store.
///
/// Design intent (from the memorization strategy):
///  1. SABAQ  — a small new portion (3–10 lines of the Madani mushaf), sized down
///     after weak days. A portion counts as memorized only on one flawless recall.
///  2. SABQI  — everything memorized in the last 7 days, recited *before* any new
///     Sabaq. No new Sabaq until today's Sabqi is cleared.
///  3. MANZIL — all older material, kept fresh so the whole ḥifẓ is seen within a
///     bounded window. Manzil itself lives in `HifzPageScheduler`, which schedules
///     it per page against a hard 30-day cap; this type covers Sabaq and Sabqi.
enum HifzProgram {

    // MARK: - Portion sizing (Sabaq)

    static let linesPerPage = 15.0
    static var ayahsPerPage: Double { Double(QuranData.totalAyahs) / Double(QuranData.totalPages) }

    /// A "lines" portion expressed as a whole number of ayahs using the mushaf-wide
    /// average. This is for *forecasting a pace* — "a quarter page ≈ N ayahs/day",
    /// where an average over the whole mushaf is exactly what's wanted.
    ///
    /// It is deliberately **not** how a day's actual lesson is sized: the average
    /// is blind to where in the mushaf you are. Today's portion is measured against
    /// the real printed layout — see `nextSabaqAtoms(…lines:…)`.
    static func ayahCount(forLines lines: Int) -> Int {
        max(1, Int((Double(lines) / linesPerPage * ayahsPerPage).rounded()))
    }

    /// Portion size in lines around the chosen base (the user's daily-lesson unit,
    /// 1…15), nudged by recent accuracy (0…1): shrink after weak days, grow after
    /// strong ones. Clamped to 1 line … one page so the chosen unit is honored.
    static func portionLines(baseLines: Int = 5, recentAccuracy: Double) -> Int {
        let adjusted: Int
        switch recentAccuracy {
        case ..<0.6:  adjusted = baseLines - 2
        case ..<0.85: adjusted = baseLines
        default:      adjusted = baseLines + 2
        }
        return min(MushafUnitKind.page.baseLines, max(1, adjusted))
    }

    /// Recall accuracy from recent session outcomes (1.0 == flawless, no data == 1.0).
    static func recentAccuracy(reviews: Int, mistakes: Int) -> Double {
        guard reviews > 0 else { return 1 }
        return max(0, 1 - Double(mistakes) / Double(reviews))
    }

    /// The still-unlearned atoms in the order Sabaq should take them.
    ///
    /// By default that is mushaf order (Al-Fātiḥa → An-Nās). With `fromEnd` the
    /// surah sequence runs from the end of the mushaf instead (An-Nās →
    /// Al-Fātiḥa) — the common back-to-front path that starts on the short surahs
    /// of Juzʼ ʻAmma and works toward the long ones. Ayahs within a surah always
    /// stay ascending, since a surah is memorized top-to-bottom.
    static func unlearnedAtoms(
        orderedAtoms: [(surah: Int, ayah: Int, page: Int, juz: Int)],
        memorizedOrInProgressKeys: Set<String>,
        fromEnd: Bool = false
    ) -> [(surah: Int, ayah: Int, page: Int, juz: Int)] {
        let ordered = fromEnd
            ? orderedAtoms.sorted { $0.surah != $1.surah ? $0.surah > $1.surah : $0.ayah < $1.ayah }
            : orderedAtoms
        return ordered.filter {
            !memorizedOrInProgressKeys.contains(HifzAyah.makeKey(surah: $0.surah, ayah: $0.ayah))
        }
    }

    /// The next `count` unmemorized ayahs for a fresh Sabaq portion.
    static func nextSabaqAtoms(
        orderedAtoms: [(surah: Int, ayah: Int, page: Int, juz: Int)],
        memorizedOrInProgressKeys: Set<String>,
        count: Int,
        fromEnd: Bool = false
    ) -> [(surah: Int, ayah: Int, page: Int, juz: Int)] {
        Array(
            unlearnedAtoms(orderedAtoms: orderedAtoms,
                           memorizedOrInProgressKeys: memorizedOrInProgressKeys,
                           fromEnd: fromEnd)
                .prefix(max(0, count))
        )
    }

    /// Today's Sabaq portion, sized against the **real printed mushaf** rather than
    /// a mushaf-wide average: ayahs are taken in learning order until their combined
    /// printed length comes closest to `lines` lines.
    ///
    /// This is the difference between a nominal and an actual portion. A line of
    /// Juzʼ ʻAmma holds several short ayahs, while a single ayah of Al-Baqara can
    /// fill a page — so a fixed ayah count means wildly different amounts of page
    /// depending on where you are. Measuring in lines keeps the daily load constant.
    ///
    /// An ayah joins the portion while it brings the total *nearer* to the target
    /// than stopping would; at least one ayah is always picked, even when it alone
    /// is longer than the whole target.
    static func nextSabaqAtoms(
        orderedAtoms: [(surah: Int, ayah: Int, page: Int, juz: Int)],
        memorizedOrInProgressKeys: Set<String>,
        lines: Int,
        fromEnd: Bool = false,
        lineCost: (Int, Int) -> Double = { MushafLayout.lineCost(surah: $0, ayah: $1) }
    ) -> [(surah: Int, ayah: Int, page: Int, juz: Int)] {
        let target = Double(max(1, lines))
        var out: [(surah: Int, ayah: Int, page: Int, juz: Int)] = []
        var total = 0.0
        for atom in unlearnedAtoms(orderedAtoms: orderedAtoms,
                                   memorizedOrInProgressKeys: memorizedOrInProgressKeys,
                                   fromEnd: fromEnd) {
            let cost = max(0, lineCost(atom.surah, atom.ayah))
            // Nearest rounding: stop once this ayah would overshoot by more than
            // it closes the remaining gap.
            if !out.isEmpty, total + cost / 2 > target { break }
            out.append(atom)
            total += cost
        }
        return out
    }

    // MARK: - Sabqi (recent revision, blocking)

    /// Ayahs memorized within the last `days` days **that are due today**. Recited
    /// in mushaf order by default; with `fromEnd` the surah sequence runs from the
    /// end of the mushaf (An-Nās → Al-Fātiḥa) so review follows the same
    /// back-to-front path as a from-the-end Sabaq.
    ///
    /// An ayah reviewed today (e.g. the lesson just confirmed, or a Sabqi recital
    /// completed) has its `dueDate` pushed into the future and so drops out of
    /// today's queue, reappearing only on its next scheduled day — it is not
    /// re-listed as fällig the same day. A `nil` `dueDate` (legacy or seeded rows
    /// that were never scheduled) is treated as due.
    static func sabqiQueue(
        _ ayahs: [HifzAyah],
        now: Date = .now,
        days: Int = 7,
        fromEnd: Bool = false,
        calendar: Calendar = .current
    ) -> [HifzAyah] {
        let start = calendar.startOfDay(for: now)
        guard let cutoff = calendar.date(byAdding: .day, value: -days, to: start) else { return [] }
        return ayahs
            .filter { ($0.memorizedAt ?? .distantPast) >= cutoff }
            .filter { isDue($0.dueDate, on: start, calendar: calendar) }
            .sorted(by: mushafOrder(fromEnd: fromEnd))
    }

    /// Whether a scheduled item is due on `day`: never-scheduled (`nil`) counts as
    /// due; otherwise its due date must have arrived (start-of-day ≤ `day`).
    static func isDue(_ dueDate: Date?, on day: Date, calendar: Calendar = .current) -> Bool {
        guard let due = dueDate else { return true }
        return calendar.startOfDay(for: due) <= day
    }

    /// New Sabaq is only allowed once today's Sabqi is empty or has been cleared.
    static func isSabaqUnlocked(
        sabqiCount: Int,
        sabqiClearedOn: Date?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        if sabqiCount == 0 { return true }
        guard let cleared = sabqiClearedOn else { return false }
        return calendar.isDate(cleared, inSameDayAs: now)
    }

    // MARK: - Weak links

    /// Memorized ayahs missed repeatedly, worst first — targets for extra reps.
    static func weakLinks(_ ayahs: [HifzAyah], threshold: Int = 3) -> [HifzAyah] {
        ayahs
            .filter { $0.isMemorized && $0.mistakeCount >= threshold }
            .sorted { $0.mistakeCount > $1.mistakeCount }
    }

    // MARK: - Ordering

    static func mushafOrder(_ a: HifzAyah, _ b: HifzAyah) -> Bool {
        (a.surah, a.ayah) < (b.surah, b.ayah)
    }

    /// A mushaf-order comparator, optionally reversed to run from the end of the
    /// mushaf (An-Nās → Al-Fātiḥa). Ayahs within a surah always stay ascending —
    /// a surah is memorized and recited top-to-bottom regardless of direction.
    static func mushafOrder(fromEnd: Bool) -> (HifzAyah, HifzAyah) -> Bool {
        guard fromEnd else { return mushafOrder }
        return { $0.surah != $1.surah ? $0.surah > $1.surah : $0.ayah < $1.ayah }
    }
}
