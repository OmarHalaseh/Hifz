import Foundation

/// Sabaq / Sabqi / Manzil scheduling. Page state is *derived* by aggregating the
/// underlying `HifzAyah` rows — no separate page model is stored, so a page's
/// freshness, interval and strength all fall out of its ayahs' spaced-repetition
/// state.
///
/// Daily Manzil is picked in **revision blocks** rather than raw pages: a short
/// surah (≤ two pages) is one block and always revised whole, while a long surah
/// is split into page-sized parts so Al-Baqara is spread over many days.
///
/// Manzil enforces a **hard 30-day cap**:
///
///     nextDue = lastReviewed + min(srInterval, 30)
///
/// guaranteeing every memorized page — and therefore every surah — is reviewed at
/// least once a month. A mistake shrinks a page's interval (via its ayahs) so it
/// returns sooner; flawless recall grows it, but never past the cap.
///
/// The daily Manzil load is budgeted in **lines** (never in number of surahs): a
/// long surah such as Al-Baqara spans many pages and is split across days, and
/// each page keeps its own ≤30-day guarantee independently.
///
/// Pure decision logic only — no SwiftData or UI — so it is unit-testable by
/// constructing `PageState` values directly.
enum HifzPageScheduler {

    /// The hard ceiling (days) on a Manzil page's review interval.
    static let manzilCapDays = 30

    /// The recent-revision window (days) that defines Sabqi.
    static let sabqiDays = 7

    /// Mistakes per ayah at which page strength bottoms out at 0.
    static let mistakeSaturation = 5.0

    // MARK: - Aggregated page state (value type, derived from ayahs)

    /// A page as a scheduling unit, aggregated from its `HifzAyah` rows.
    /// CloudKit-irrelevant: it is a derived value, never persisted.
    struct PageState: Hashable, Identifiable {
        let page: Int
        let surah: Int          // primary surah printed on the page
        let juz: Int
        let tier: HifzPhase
        let lastReviewed: Date?
        let srInterval: Int     // days; the weakest ayah drives the page
        let strength: Double    // 0 (weak) … 1 (strong)
        let lineCount: Int      // memorizable text lines on the page
        let memorizedAt: Date?  // when the page became fully memorized

        var id: Int { page }

        /// Next Manzil due date under the 30-day cap. A page never reviewed since it
        /// was memorized is treated as due immediately (`.distantPast`).
        func nextDue(cap: Int = HifzPageScheduler.manzilCapDays, calendar: Calendar = .current) -> Date {
            guard let last = lastReviewed else { return .distantPast }
            return calendar.date(byAdding: .day, value: min(srInterval, cap),
                                 to: calendar.startOfDay(for: last)) ?? .distantPast
        }
    }

    // MARK: - Queues

    /// Fully-memorized pages that entered the ḥifẓ within the Sabqi window — recited
    /// in full every day, ahead of the long-term cycle. In mushaf (page) order.
    static func sabqiQueue(_ pages: [PageState]) -> [PageState] {
        pages.filter { $0.tier == .sabqi }.sorted { $0.page < $1.page }
    }

    /// Today's Manzil slice: pages whose 30-day-capped due date has arrived,
    /// **most overdue first**, filled up to `lineBudget` lines. The most-overdue
    /// page is always included even if it alone exceeds the budget, so no page can
    /// starve; ordering by urgency keeps the 30-day guarantee whenever the budget is
    /// large enough for the volume, and degrades gracefully (oldest-first) if not.
    static func manzilQueue(
        _ pages: [PageState],
        lineBudget: Int,
        now: Date = .now,
        fromEnd: Bool = false,
        calendar: Calendar = .current
    ) -> [PageState] {
        let today = calendar.startOfDay(for: now)
        let due = pages
            .filter { $0.tier == .manzil && $0.nextDue(calendar: calendar) <= today }
            .sorted { lhs, rhs in
                let l = lhs.nextDue(calendar: calendar), r = rhs.nextDue(calendar: calendar)
                // Most overdue first; ties broken toward the end of the mushaf when
                // reviewing from the end, otherwise front-first.
                return l == r ? (fromEnd ? lhs.page > rhs.page : lhs.page < rhs.page) : l < r
            }

        var out: [PageState] = []
        var lines = 0
        for page in due {
            if out.isEmpty || lines + page.lineCount <= lineBudget {
                out.append(page)
                lines += page.lineCount
            } else {
                break
            }
        }
        return out
    }

    // MARK: - Day budgeting (lines)

    /// Manzil pages to cover per day so the whole long-term set is seen within the
    /// 30-day cap: `ceil(manzilPageCount / 30)`, at least one.
    static func manzilPagesPerDay(_ pages: [PageState]) -> Int {
        let count = pages.lazy.filter { $0.tier == .manzil }.count
        guard count > 0 else { return 0 }
        return max(1, Int((Double(count) / Double(manzilCapDays)).rounded(.up)))
    }

    /// A daily Manzil **line** budget that is always enough to pack
    /// `manzilPagesPerDay` full pages, so line-budgeting can't undershoot the
    /// 30-day guarantee on discrete page boundaries.
    static func lineBudget(manzilPages pages: [PageState]) -> Int {
        manzilPagesPerDay(pages) * MushafUnitKind.page.baseLines
    }

    // MARK: - Store/bundle-backed builders

    /// Today's due Manzil pages for a set of `HifzAyah` rows, using the real mushaf
    /// line layout and page membership.
    static func todaysManzilPages(
        from ayahs: [HifzAyah], now: Date = .now, fromEnd: Bool = false,
        calendar: Calendar = .current
    ) -> [PageState] {
        let pages = pageStates(from: ayahs, now: now, calendar: calendar)
        return manzilQueue(pages, lineBudget: lineBudget(manzilPages: pages),
                           now: now, fromEnd: fromEnd, calendar: calendar)
    }

    /// The memorized `HifzAyah` rows due for Manzil today, in recitation order —
    /// the ready-to-drill set for a Manzil session. Selection runs on **revision
    /// blocks** (see `revisionBlocks`), so a short surah is always revised whole and
    /// a long one a page at a time. With `fromEnd`, block selection and recitation
    /// order both run from the end of the mushaf (An-Nās first).
    static func manzilDueAyahs(
        from ayahs: [HifzAyah], now: Date = .now, fromEnd: Bool = false,
        calendar: Calendar = .current
    ) -> [HifzAyah] {
        let blocks = revisionBlocks(from: ayahs, now: now, calendar: calendar)
        let due = blockQueue(blocks, lineBudget: blockLineBudget(blocks),
                             now: now, fromEnd: fromEnd, calendar: calendar)
        let keys = Set(due.flatMap(\.ayahKeys))
        return ayahs
            .filter { $0.isMemorized && keys.contains($0.key) }
            .sorted(by: HifzProgram.mushafOrder(fromEnd: fromEnd))
    }

    // MARK: - Revision blocks (surah-aware Manzil units)

    /// A surah whose memorized part fits in this many printed lines (two pages) is
    /// revised in one sitting. Splitting it — as pure page scheduling does when a
    /// short surah straddles a page break — leaves you reciting half a surah.
    static let wholeSurahMaxLines = 2.0 * Double(MushafUnitKind.page.baseLines)

    /// A page-part of a long surah shorter than this is folded into its neighbour,
    /// so a surah that ends three lines into a page doesn't become a separate,
    /// three-line revision.
    static let minPartLines = 5.0

    /// One unit of long-term revision: a whole short surah, or one page-sized part
    /// of a long one (e.g. Al-Baqara part 7 of 48). Derived from `HifzAyah` rows,
    /// never persisted. Its freshness is that of its least-recently-reviewed ayah.
    struct RevisionBlock: Hashable, Identifiable {
        let surah: Int
        let part: Int           // 1-based; 1 for a whole surah
        let partCount: Int
        let firstPage: Int
        let lastPage: Int
        let ayahKeys: [String]
        let firstAyah: Int
        let lastAyah: Int
        let lines: Double
        let lastReviewed: Date?
        let srInterval: Int

        var id: String { "\(surah)-\(part)" }
        var isWholeSurah: Bool { partCount == 1 }

        /// Next due date under the 30-day cap; never reviewed → due now.
        func nextDue(cap: Int = HifzPageScheduler.manzilCapDays, calendar: Calendar = .current) -> Date {
            guard let last = lastReviewed else { return .distantPast }
            return calendar.date(byAdding: .day, value: min(srInterval, cap),
                                 to: calendar.startOfDay(for: last)) ?? .distantPast
        }
    }

    /// The scheduling fields of one memorized ayah, as a plain value — so blocks
    /// can be built from live `HifzAyah` rows or from a simulated future state
    /// (the revision forecast in `HifzPlan`).
    struct AyahSnapshot: Hashable {
        var key: String
        var surah: Int
        var ayah: Int
        var page: Int
        var memorizedAt: Date?
        var lastReviewedAt: Date?
        var intervalDays: Int
        var repetitions: Int
        var easeFactor: Double

        init(_ row: HifzAyah) {
            key = row.key; surah = row.surah; ayah = row.ayah; page = row.page
            memorizedAt = row.memorizedAt; lastReviewedAt = row.lastReviewedAt
            intervalDays = row.intervalDays; repetitions = row.repetitions
            easeFactor = row.easeFactor
        }

        init(surah: Int, ayah: Int, page: Int, memorizedAt: Date?, lastReviewedAt: Date? = nil,
             intervalDays: Int = 0, repetitions: Int = 0, easeFactor: Double = 2.5) {
            self.key = HifzAyah.makeKey(surah: surah, ayah: ayah)
            self.surah = surah; self.ayah = ayah; self.page = page
            self.memorizedAt = memorizedAt; self.lastReviewedAt = lastReviewedAt
            self.intervalDays = intervalDays; self.repetitions = repetitions
            self.easeFactor = easeFactor
        }
    }

    static func revisionBlocks(
        from ayahs: [HifzAyah],
        lineCost: (Int, Int) -> Double = { MushafLayout.lineCost(surah: $0, ayah: $1) },
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [RevisionBlock] {
        revisionBlocks(from: ayahs.map(AyahSnapshot.init), lineCost: lineCost, now: now, calendar: calendar)
    }

    /// Groups memorized, Manzil-age ayahs (memorized before the Sabqi window) into
    /// revision blocks. Recent ayahs are left to Sabqi, which recites them daily.
    static func revisionBlocks(
        from ayahs: [AyahSnapshot],
        lineCost: (Int, Int) -> Double = { MushafLayout.lineCost(surah: $0, ayah: $1) },
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [RevisionBlock] {
        guard let cutoff = calendar.date(byAdding: .day, value: -sabqiDays,
                                         to: calendar.startOfDay(for: now)) else { return [] }
        let eligible = ayahs.filter { ($0.memorizedAt ?? .distantFuture) < cutoff }

        var out: [RevisionBlock] = []
        for (surah, rows) in Dictionary(grouping: eligible, by: \.surah) {
            let sorted = rows.sorted { $0.ayah < $1.ayah }
            func cost(_ a: AyahSnapshot) -> Double { max(0, lineCost(a.surah, a.ayah)) }
            let total = sorted.reduce(0) { $0 + cost($1) }

            var parts: [[AyahSnapshot]]
            if total <= wholeSurahMaxLines {
                parts = [sorted]
            } else {
                parts = []
                for row in sorted {
                    if let last = parts.last?.last, last.page == row.page {
                        parts[parts.count - 1].append(row)
                    } else {
                        parts.append([row])
                    }
                }
                // Fold slivers into the previous part (or the next, for the first).
                var merged: [[AyahSnapshot]] = []
                for part in parts {
                    let lines = part.reduce(0) { $0 + cost($1) }
                    if lines < minPartLines, !merged.isEmpty {
                        merged[merged.count - 1].append(contentsOf: part)
                    } else {
                        merged.append(part)
                    }
                }
                if merged.count > 1, merged[0].reduce(0, { $0 + cost($1) }) < minPartLines {
                    merged[1].insert(contentsOf: merged.removeFirst(), at: 0)
                }
                parts = merged
            }

            for (i, part) in parts.enumerated() {
                out.append(RevisionBlock(
                    surah: surah,
                    part: i + 1,
                    partCount: parts.count,
                    firstPage: part.map(\.page).min() ?? 0,
                    lastPage: part.map(\.page).max() ?? 0,
                    ayahKeys: part.map(\.key),
                    firstAyah: part.first?.ayah ?? 0,
                    lastAyah: part.last?.ayah ?? 0,
                    lines: part.reduce(0) { $0 + cost($1) },
                    lastReviewed: part.compactMap { $0.lastReviewedAt ?? $0.memorizedAt }.min(),
                    srInterval: part.map(\.intervalDays).min() ?? 0
                ))
            }
        }
        return out.sorted { ($0.surah, $0.part) < ($1.surah, $1.part) }
    }

    /// Daily line budget that covers every block within the 30-day cap, in whole
    /// pages: `ceil(totalLines / 30)` rounded up to a page, at least one page.
    static func blockLineBudget(_ blocks: [RevisionBlock]) -> Int {
        let total = blocks.reduce(0) { $0 + $1.lines }
        guard total > 0 else { return 0 }
        let page = MushafUnitKind.page.baseLines
        let perDay = Int((total / Double(manzilCapDays)).rounded(.up))
        return max(page, Int((Double(perDay) / Double(page)).rounded(.up)) * page)
    }

    /// Today's Manzil blocks: due blocks, most overdue first, filled up to
    /// `lineBudget`. The most overdue block is always taken so nothing starves.
    /// Ties go toward the reading direction, then to the earlier part of a surah.
    static func blockQueue(
        _ blocks: [RevisionBlock],
        lineBudget: Int,
        now: Date = .now,
        fromEnd: Bool = false,
        calendar: Calendar = .current
    ) -> [RevisionBlock] {
        let today = calendar.startOfDay(for: now)
        let due = blocks
            .filter { $0.nextDue(calendar: calendar) <= today }
            .sorted { lhs, rhs in
                let l = lhs.nextDue(calendar: calendar), r = rhs.nextDue(calendar: calendar)
                if l != r { return l < r }
                if lhs.surah != rhs.surah { return fromEnd ? lhs.surah > rhs.surah : lhs.surah < rhs.surah }
                return lhs.part < rhs.part
            }

        var out: [RevisionBlock] = []
        var lines = 0.0
        for block in due {
            if out.isEmpty || lines + block.lines <= Double(lineBudget) {
                out.append(block)
                lines += block.lines
            } else {
                break
            }
        }
        return out
    }

    /// Aggregates `HifzAyah` rows into one `PageState` per page, using the real
    /// mushaf line counts and full page membership from the bundled layout.
    static func pageStates(
        from ayahs: [HifzAyah], now: Date = .now, calendar: Calendar = .current
    ) -> [PageState] {
        pageStates(
            from: ayahs,
            lineCountOnPage: { MushafLayout.textLines(onPage: $0).count },
            ayahKeysOnPage: { MemorizationCoverage.pageAyahKeys($0) },
            now: now, calendar: calendar
        )
    }

    /// Testable core of the aggregation: page line counts and full page membership
    /// are injected so it needs no bundle. A page appears once it has ≥1 memorized
    /// ayah; its `tier` is `.sabaq` until every ayah printed on the page is memorized,
    /// then `.sabqi` for the recent-revision window, then `.manzil`.
    static func pageStates(
        from ayahs: [HifzAyah],
        lineCountOnPage: (Int) -> Int,
        ayahKeysOnPage: (Int) -> [String],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [PageState] {
        let memorized = ayahs.filter(\.isMemorized)
        guard !memorized.isEmpty else { return [] }
        let sabqiCutoff = calendar.date(byAdding: .day, value: -sabqiDays, to: calendar.startOfDay(for: now))

        return Dictionary(grouping: memorized, by: \.page).map { page, rows -> PageState in
            let sorted = rows.sorted(by: HifzProgram.mushafOrder)
            let memoKeys = Set(rows.map(\.key))
            let membership = ayahKeysOnPage(page)
            let fullyMemorized = membership.isEmpty || membership.allSatisfy(memoKeys.contains)

            // A page is as fresh as its least-recently-touched ayah; an ayah never
            // revised since it was memorized counts as reviewed at memorization time.
            let lastReviewed = rows.compactMap { $0.lastReviewedAt ?? $0.memorizedAt }.min()
            let srInterval = rows.map(\.intervalDays).min() ?? 0
            let totalMistakes = rows.reduce(0) { $0 + $1.mistakeCount }
            let strength = max(0, 1 - Double(totalMistakes) / (Double(rows.count) * mistakeSaturation))
            let pageMemorizedAt = fullyMemorized ? rows.compactMap(\.memorizedAt).max() : nil

            let tier: HifzPhase
            if !fullyMemorized {
                tier = .sabaq
            } else if let m = pageMemorizedAt, let cut = sabqiCutoff, m >= cut {
                tier = .sabqi
            } else {
                tier = .manzil
            }

            return PageState(
                page: page,
                surah: sorted.first?.surah ?? 0,
                juz: sorted.first?.juz ?? 0,
                tier: tier,
                lastReviewed: lastReviewed,
                srInterval: srInterval,
                strength: strength,
                lineCount: lineCountOnPage(page),
                memorizedAt: pageMemorizedAt
            )
        }
        .sorted { $0.page < $1.page }
    }
}
