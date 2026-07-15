import Foundation

/// Page-level Sabaq / Sabqi / Manzil scheduling. The scheduling **unit is the
/// mushaf page**, but page state is *derived* by aggregating the underlying
/// `HifzAyah` rows — no separate page model is stored, so a page's freshness,
/// interval and strength all fall out of its ayahs' spaced-repetition state.
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

    /// The memorized `HifzAyah` rows on today's due Manzil pages, in mushaf order —
    /// the ready-to-drill set for a Manzil session. With `fromEnd`, page selection
    /// and recitation order both run from the end of the mushaf (An-Nās first).
    static func manzilDueAyahs(
        from ayahs: [HifzAyah], now: Date = .now, fromEnd: Bool = false,
        calendar: Calendar = .current
    ) -> [HifzAyah] {
        let duePages = Set(todaysManzilPages(from: ayahs, now: now, fromEnd: fromEnd,
                                             calendar: calendar).map(\.page))
        return ayahs
            .filter { $0.isMemorized && duePages.contains($0.page) }
            .sorted(by: HifzProgram.mushafOrder(fromEnd: fromEnd))
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
