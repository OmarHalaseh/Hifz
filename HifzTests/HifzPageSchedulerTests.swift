import XCTest
@testable import Hifz

/// Unit tests for the page-level Sabaq / Sabqi / Manzil scheduler. Store-free:
/// `PageState` values are built directly, so no bundle or SwiftData is needed.
final class HifzPageSchedulerTests: XCTestCase {

    private let cal = Calendar.current

    /// A fully-memorized Manzil page, reviewed `reviewedDaysAgo` days before `now`,
    /// carrying a (possibly large) SM-2 interval and a given line count.
    private func manzilPage(
        _ page: Int, surah: Int = 2, juz: Int = 1,
        reviewedDaysAgo: Int, srInterval: Int, lineCount: Int = 15, now: Date
    ) -> HifzPageScheduler.PageState {
        let last = cal.date(byAdding: .day, value: -reviewedDaysAgo, to: now)
        return HifzPageScheduler.PageState(
            page: page, surah: surah, juz: juz, tier: .manzil,
            lastReviewed: last, srInterval: srInterval, strength: 1,
            lineCount: lineCount, memorizedAt: last
        )
    }

    // MARK: - The hard 30-day cap

    /// A page whose SM-2 interval has grown to 90 days must still surface by day 30:
    /// `nextDue = lastReviewed + min(srInterval, 30)`.
    func testManzilCapForcesReviewByDay30EvenWithLargeInterval() {
        let now = Date()

        // Reviewed exactly 30 days ago, interval 90 → uncapped it would be 60 days
        // out, but the cap pulls it due today.
        let capped = manzilPage(5, reviewedDaysAgo: 30, srInterval: 90, now: now)
        XCTAssertEqual(
            HifzPageScheduler.manzilQueue([capped], lineBudget: 100, now: now).map(\.page),
            [5],
            "A page last seen 30 days ago must be due today regardless of its SM-2 interval."
        )

        // Reviewed only 20 days ago with the same interval → not yet due (the cap is
        // a ceiling, it doesn't drag pages forward before 30 days).
        let notYet = manzilPage(6, reviewedDaysAgo: 20, srInterval: 90, now: now)
        XCTAssertTrue(
            HifzPageScheduler.manzilQueue([notYet], lineBudget: 100, now: now).isEmpty,
            "A page seen 20 days ago with a 30-day cap is not due yet."
        )

        // The guarantee holds for every page independently: none can be scheduled
        // beyond the cap.
        for daysAgo in [0, 5, 15, 29] {
            let p = manzilPage(7, reviewedDaysAgo: daysAgo, srInterval: 365, now: now)
            let dueDay = cal.dateComponents([.day], from: p.nextDue(), to: p.lastReviewed!).day.map(abs) ?? 0
            XCTAssertLessThanOrEqual(dueDay, HifzPageScheduler.manzilCapDays)
        }
    }

    // MARK: - Line-budget split of a long surah

    /// Al-Baqara spans dozens of pages; the daily Manzil load is budgeted in lines,
    /// so it is split across days rather than all revised at once — and each page
    /// keeps its own independent ≤30-day guarantee.
    func testLineBudgetSplitsLongSurahAcrossDaysWithin30DayCap() {
        let now = Date()
        // ~48 mushaf pages of Al-Baqara, all long-memorized → all Manzil, all due.
        let pageNumbers = Array(2...49)
        let pages = pageNumbers.map {
            manzilPage($0, reviewedDaysAgo: 40, srInterval: 15, lineCount: 15, now: now)
        }

        let budget = HifzPageScheduler.lineBudget(manzilPages: pages)
        let today = HifzPageScheduler.manzilQueue(pages, lineBudget: budget, now: now)

        // 1) The whole surah is NOT crammed into one day — it is split.
        XCTAssertGreaterThan(pages.count, today.count,
                             "A long surah must be spread across days, not all at once.")
        XCTAssertFalse(today.isEmpty)

        // 2) Today's load respects the line budget.
        XCTAssertLessThanOrEqual(today.reduce(0) { $0 + $1.lineCount }, budget,
                                 "Daily Manzil load must stay within the line budget.")

        // 3) The budget guarantees full coverage within the 30-day cap:
        //    pagesPerDay * 30 ≥ total pages.
        let perDay = HifzPageScheduler.manzilPagesPerDay(pages)
        XCTAssertGreaterThanOrEqual(perDay * HifzPageScheduler.manzilCapDays, pages.count,
                                    "The daily budget must cover every page within 30 days.")

        // 4) Each page keeps its OWN ≤30-day due date, independent of the others.
        for p in pages {
            let interval = cal.dateComponents([.day], from: p.lastReviewed!, to: p.nextDue()).day ?? 0
            XCTAssertLessThanOrEqual(interval, HifzPageScheduler.manzilCapDays)
        }

        // 5) Simulating consecutive days covers the entire surah within the cap.
        var seen = Set<Int>()
        var remaining = pages
        var day = 0
        while !remaining.isEmpty && day < HifzPageScheduler.manzilCapDays {
            let slice = HifzPageScheduler.manzilQueue(remaining, lineBudget: budget, now: now)
            slice.forEach { seen.insert($0.page) }
            let done = Set(slice.map(\.page))
            remaining.removeAll { done.contains($0.page) }
            day += 1
        }
        XCTAssertEqual(seen, Set(pageNumbers),
                       "Every page of the long surah is reviewed within 30 days.")
    }

    // MARK: - Budgeting & queue mechanics

    func testMostOverduePageIsAlwaysIncludedEvenIfItExceedsBudget() {
        let now = Date()
        // A single page larger than the budget must still be scheduled (no starving).
        let big = manzilPage(10, reviewedDaysAgo: 40, srInterval: 10, lineCount: 15, now: now)
        let queue = HifzPageScheduler.manzilQueue([big], lineBudget: 5, now: now)
        XCTAssertEqual(queue.map(\.page), [10])
    }

    func testManzilQueueOrdersMostOverdueFirst() {
        let now = Date()
        let a = manzilPage(3, reviewedDaysAgo: 31, srInterval: 5, now: now)  // 26 days overdue
        let b = manzilPage(4, reviewedDaysAgo: 40, srInterval: 5, now: now)  // 35 days overdue
        let c = manzilPage(5, reviewedDaysAgo: 33, srInterval: 5, now: now)  // 28 days overdue
        let queue = HifzPageScheduler.manzilQueue([a, b, c], lineBudget: 100, now: now)
        XCTAssertEqual(queue.map(\.page), [4, 5, 3], "Most overdue pages come first.")
    }

    func testManzilQueueFromEndBreaksDueDateTiesTowardEndOfMushaf() {
        let now = Date()
        // Three equally-overdue pages: urgency is identical, so only the tie-break differs.
        let p3 = manzilPage(3, reviewedDaysAgo: 40, srInterval: 5, now: now)
        let p20 = manzilPage(20, reviewedDaysAgo: 40, srInterval: 5, now: now)
        let p100 = manzilPage(100, reviewedDaysAgo: 40, srInterval: 5, now: now)

        let front = HifzPageScheduler.manzilQueue([p3, p20, p100], lineBudget: 100, now: now)
        XCTAssertEqual(front.map(\.page), [3, 20, 100], "Ties favor the front of the mushaf by default.")

        let end = HifzPageScheduler.manzilQueue([p3, p20, p100], lineBudget: 100, now: now, fromEnd: true)
        XCTAssertEqual(end.map(\.page), [100, 20, 3], "From the end, ties favor later pages first.")
    }

    func testSabqiPagesAreExcludedFromManzil() {
        let now = Date()
        let manzil = manzilPage(8, reviewedDaysAgo: 40, srInterval: 10, now: now)
        let sabqi = HifzPageScheduler.PageState(
            page: 9, surah: 2, juz: 1, tier: .sabqi,
            lastReviewed: now, srInterval: 0, strength: 1, lineCount: 15, memorizedAt: now
        )
        let queue = HifzPageScheduler.manzilQueue([manzil, sabqi], lineBudget: 100, now: now)
        XCTAssertEqual(queue.map(\.page), [8], "Recent (Sabqi) pages are not in the Manzil cycle.")
        XCTAssertEqual(HifzPageScheduler.sabqiQueue([manzil, sabqi]).map(\.page), [9])
    }

    // MARK: - Aggregation of ayah rows into page state

    func testPageIsManzilOnlyWhenEveryAyahOnItIsMemorized() {
        let now = Date()
        let memorizedAt = cal.date(byAdding: .day, value: -40, to: now)!
        // Page 1 has three ayahs printed on it; only two are memorized.
        let a1 = HifzAyah(surah: 1, ayah: 1, page: 1, juz: 1)
        let a2 = HifzAyah(surah: 1, ayah: 2, page: 1, juz: 1)
        for a in [a1, a2] { a.memorizedAt = memorizedAt; a.lastReviewedAt = memorizedAt; a.intervalDays = 10 }

        let membership: (Int) -> [String] = { _ in ["1:1", "1:2", "1:3"] }  // third not memorized
        let partial = HifzPageScheduler.pageStates(
            from: [a1, a2], lineCountOnPage: { _ in 15 }, ayahKeysOnPage: membership, now: now
        )
        XCTAssertEqual(partial.first?.tier, .sabaq, "A partially-memorized page is still Sabaq.")

        // Now memorize the third ayah → the page completes and (long ago) becomes Manzil.
        let a3 = HifzAyah(surah: 1, ayah: 3, page: 1, juz: 1)
        a3.memorizedAt = memorizedAt; a3.lastReviewedAt = memorizedAt; a3.intervalDays = 10
        let full = HifzPageScheduler.pageStates(
            from: [a1, a2, a3], lineCountOnPage: { _ in 15 }, ayahKeysOnPage: membership, now: now
        )
        XCTAssertEqual(full.first?.tier, .manzil, "A fully-memorized, long-ago page is Manzil.")
        XCTAssertEqual(full.first?.srInterval, 10, "Page interval is its weakest ayah's interval.")
    }
}
