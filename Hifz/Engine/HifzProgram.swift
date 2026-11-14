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
    /// is longer than the whole target. The lesson stops at the end of a surah —
    /// see `portionCount` for the exact rule.
    static func nextSabaqAtoms(
        orderedAtoms: [(surah: Int, ayah: Int, page: Int, juz: Int)],
        memorizedOrInProgressKeys: Set<String>,
        lines: Int,
        fromEnd: Bool = false,
        lineCost: (Int, Int) -> Double = { MushafLayout.lineCost(surah: $0, ayah: $1) }
    ) -> [(surah: Int, ayah: Int, page: Int, juz: Int)] {
        let unlearned = unlearnedAtoms(orderedAtoms: orderedAtoms,
                                       memorizedOrInProgressKeys: memorizedOrInProgressKeys,
                                       fromEnd: fromEnd)
        let n = portionCount(count: unlearned.count, lines: lines,
                             surah: { unlearned[$0].surah },
                             cost: { lineCost(unlearned[$0].surah, unlearned[$0].ayah) })
        return Array(unlearned.prefix(n))
    }

    /// How many items of a learning-ordered sequence, starting at `start`, make up
    /// one Sabaq portion of about `lines` printed lines. The single rule shared by
    /// the real lesson and the plan's projection, so they can't drift apart.
    ///
    /// - An ayah joins while it brings the total *nearer* to the target than
    ///   stopping would; at least one is always taken.
    /// - **A lesson ends at the end of a surah.** It only continues into the next
    ///   surah when that surah fits *whole* — so a new surah always starts at its
    ///   first ayah at the top of a lesson, or is learned complete inside one
    ///   (the short surahs of Juzʼ ʻAmma). You never start a surah as the tail of
    ///   another surah's lesson and come back to its middle the next day.
    /// - A short leftover (≤ a quarter of the portion, at least one line) is folded
    ///   in, so a surah isn't left with a one-ayah lesson for tomorrow.
    static func portionCount(
        count n: Int,
        from start: Int = 0,
        lines: Int,
        surah: (Int) -> Int,
        cost: (Int) -> Double
    ) -> Int {
        let target = Double(max(1, lines))
        let tailAllowance = max(1, target * 0.25)
        var i = start
        var total = 0.0

        /// Cost of the rest of the surah beginning at `from`, and where it ends —
        /// `nil` as soon as it exceeds `limit`.
        func surahRun(from: Int, limit: Double) -> (cost: Double, end: Int)? {
            var j = from, sum = 0.0
            let s = surah(from)
            while j < n, surah(j) == s {
                sum += max(0, cost(j))
                if sum > limit { return nil }
                j += 1
            }
            return (sum, j)
        }

        while i < n {
            if i > start, surah(i) != surah(i - 1) {
                // Surah boundary: take the next surah only if all of it fits.
                guard let run = surahRun(from: i, limit: target + 0.5 - total) else { break }
                total += run.cost
                i = run.end
                continue
            }
            let c = max(0, cost(i))
            if i > start, total + c / 2 > target {
                // Full. Finish the surah anyway if only a sliver of it is left.
                if let run = surahRun(from: i, limit: tailAllowance) { i = run.end }
                break
            }
            total += c
            i += 1
        }
        return i - start
    }

    // MARK: - Sabaq drill steps

    /// How far back (in printed lines) a connecting recap reaches.
    static let recapWindowLines = 5.0

    /// `UserDefaults` key of the lesson whose drill position is remembered, so a
    /// lesson left half-way resumes at the same step.
    static let sabaqDrillLessonKey = "sabaqDrillLesson"

    /// The steps of the Sabaq drill, as index ranges into the lesson's ayahs
    /// (`costs` = each ayah's printed length in lines).
    ///
    /// Each new ayah is learned alone, then connected to what came before. The
    /// recap is a **sliding window**: it reaches back about `recapLines` lines
    /// (always at least the previous ayah) instead of restarting at the lesson's
    /// first ayah every time — on a full-page lesson that restart made the last
    /// recaps a whole page each. A final step then recites the entire lesson once.
    /// Short lessons, where everything fits in the window, stay fully cumulative.
    static func drillSteps(costs: [Double], recapLines: Double = recapWindowLines) -> [ClosedRange<Int>] {
        guard !costs.isEmpty else { return [] }
        var steps: [ClosedRange<Int>] = []
        for i in costs.indices {
            steps.append(i...i)
            guard i > 0 else { continue }
            var lower = i - 1
            var sum = costs[i] + costs[i - 1]
            while lower > 0, sum + costs[lower - 1] <= recapLines {
                lower -= 1
                sum += costs[lower]
            }
            steps.append(lower...i)
        }
        if let last = steps.last, last.count > 1, last.lowerBound != 0 {
            steps.append(0...(costs.count - 1))
        }
        return steps
    }

    // MARK: - Revision passages

    /// Default passage size (printed lines, roughly half a page) — revision is
    /// recited in passages, not ayah by ayah.
    static let revisionPassageLines = 8.0

    /// `UserDefaults` key of the user's chosen passage size, in lines.
    static let passageLinesKey = "revisionPassageLines"

    /// The passage sizes offered in Settings (lines).
    static let passageLineOptions: [(lines: Int, label: String)] = [
        (4, "Quarter page"), (8, "Half page"), (15, "Full page")
    ]

    /// The chosen passage size, falling back to the default when unset.
    static func storedPassageLines(_ defaults: UserDefaults = .standard) -> Double {
        let stored = defaults.integer(forKey: passageLinesKey)
        return stored > 0 ? Double(stored) : revisionPassageLines
    }

    /// Groups revision ayahs (already in recitation order) into **passages**: runs
    /// of consecutive ayahs of one surah, each about `maxLines` printed lines.
    ///
    /// Ḥifẓ is tested by reciting a stretch of a surah, and what breaks is usually
    /// the *join* between ayahs — which drilling isolated ayahs never exercises. A
    /// run longer than `maxLines` is split into evenly sized passages rather than
    /// full ones plus a leftover line.
    static func passages(
        _ ayahs: [HifzAyah],
        maxLines: Double = revisionPassageLines,
        lineCost: (Int, Int) -> Double = { MushafLayout.lineCost(surah: $0, ayah: $1) }
    ) -> [[HifzAyah]] {
        // 1. Contiguous runs.
        var runs: [[HifzAyah]] = []
        for a in ayahs {
            if let last = runs.last?.last, last.surah == a.surah, a.ayah == last.ayah + 1 {
                runs[runs.count - 1].append(a)
            } else {
                runs.append([a])
            }
        }
        // 2. Split each long run evenly.
        var out: [[HifzAyah]] = []
        for run in runs {
            let costs = run.map { max(0, lineCost($0.surah, $0.ayah)) }
            let total = costs.reduce(0, +)
            let parts = max(1, Int((total / max(1, maxLines)).rounded(.up)))
            let target = total / Double(parts)
            var current: [HifzAyah] = []
            var lines = 0.0
            for (a, c) in zip(run, costs) {
                if !current.isEmpty, lines + c / 2 > target {
                    out.append(current)
                    current = []
                    lines = 0
                }
                current.append(a)
                lines += c
            }
            if !current.isEmpty { out.append(current) }
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
