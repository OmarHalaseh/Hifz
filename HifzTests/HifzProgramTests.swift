import XCTest
@testable import Hifz

/// Unit tests for the pure `HifzProgram` decision logic (Sabaq / Sabqi / Manzil).
/// Everything here is store-free — `HifzAyah` rows are built in memory.
final class HifzProgramTests: XCTestCase {

    private let cal = Calendar.current

    /// A memorized ayah on a given page, memorized `daysAgo` days before `now`.
    private func ayah(surah: Int = 2, ayah: Int, page: Int, daysAgo: Int?, now: Date,
                      mistakes: Int = 0) -> HifzAyah {
        let a = HifzAyah(surah: surah, ayah: ayah, page: page, juz: 1)
        if let d = daysAgo {
            a.memorizedAt = cal.date(byAdding: .day, value: -d, to: now)
            a.phase = .sabqi
        }
        a.mistakeCount = mistakes
        return a
    }

    // MARK: - Portion sizing

    func testPortionLinesShrinksAfterWeakDaysAndGrowsAfterStrong() {
        XCTAssertEqual(HifzProgram.portionLines(recentAccuracy: 0.5), 3)   // 5 - 2
        XCTAssertEqual(HifzProgram.portionLines(recentAccuracy: 0.7), 5)   // unchanged
        XCTAssertEqual(HifzProgram.portionLines(recentAccuracy: 0.95), 7)  // 5 + 2
    }

    func testPortionLinesClampsTo1ThroughOnePage() {
        // Floor: a row (1 line) on a weak day can't go below 1.
        XCTAssertEqual(HifzProgram.portionLines(baseLines: 1, recentAccuracy: 0.5), 1)
        // Ceiling: a page (15 lines) on a strong day is capped at one page.
        XCTAssertEqual(HifzProgram.portionLines(baseLines: 15, recentAccuracy: 0.99), 15)
    }

    func testPortionLinesHonorsChosenMushafUnitAtNeutralAccuracy() {
        for unit in MushafUnitKind.allCases {
            XCTAssertEqual(
                HifzProgram.portionLines(baseLines: unit.baseLines, recentAccuracy: 0.7),
                unit.baseLines,
                "\(unit) should size its Sabaq to its own line count on a neutral day"
            )
        }
    }

    func testDefaultSabaqUnitIsQuarterPage() {
        XCTAssertEqual(AppSettings().sabaqUnit, .quarter)
    }

    func testAyahCountForLinesIsAtLeastOne() {
        XCTAssertGreaterThanOrEqual(HifzProgram.ayahCount(forLines: 1), 1)
        XCTAssertGreaterThan(HifzProgram.ayahCount(forLines: 10), HifzProgram.ayahCount(forLines: 3))
    }

    func testRecentAccuracyFromReviewsAndMistakes() {
        XCTAssertEqual(HifzProgram.recentAccuracy(reviews: 0, mistakes: 0), 1)      // no data → perfect
        XCTAssertEqual(HifzProgram.recentAccuracy(reviews: 10, mistakes: 2), 0.8, accuracy: 1e-9)
        XCTAssertEqual(HifzProgram.recentAccuracy(reviews: 4, mistakes: 8), 0)      // clamps at 0
    }

    // MARK: - Sabaq gating

    func testSabaqUnlockedWhenNoSabqi() {
        XCTAssertTrue(HifzProgram.isSabaqUnlocked(sabqiCount: 0, sabqiClearedOn: nil))
    }

    func testSabaqLockedWhenSabqiOutstandingAndUncleared() {
        XCTAssertFalse(HifzProgram.isSabaqUnlocked(sabqiCount: 5, sabqiClearedOn: nil))
    }

    func testSabaqUnlocksOnlyWhenSabqiClearedToday() {
        let now = Date()
        let yesterday = cal.date(byAdding: .day, value: -1, to: now)!
        XCTAssertTrue(HifzProgram.isSabaqUnlocked(sabqiCount: 5, sabqiClearedOn: now, now: now))
        XCTAssertFalse(HifzProgram.isSabaqUnlocked(sabqiCount: 5, sabqiClearedOn: yesterday, now: now))
    }

    func testNextSabaqAtomsSkipsMemorizedInMushafOrder() {
        let atoms: [(surah: Int, ayah: Int, page: Int, juz: Int)] = [
            (1, 1, 1, 1), (1, 2, 1, 1), (1, 3, 1, 1), (1, 4, 1, 1)
        ]
        let taken: Set<String> = [HifzAyah.makeKey(surah: 1, ayah: 1),
                                  HifzAyah.makeKey(surah: 1, ayah: 2)]
        let picked = HifzProgram.nextSabaqAtoms(orderedAtoms: atoms,
                                                memorizedOrInProgressKeys: taken, count: 1)
        XCTAssertEqual(picked.map(\.ayah), [3])
    }

    // MARK: - Sabqi (7-day window)

    func testSabqiQueueIncludesLast7DaysExcludesOlderAndUnmemorized() {
        let now = Date()
        let recentA = ayah(ayah: 1, page: 1, daysAgo: 1, now: now)
        let recentB = ayah(ayah: 2, page: 1, daysAgo: 6, now: now)
        let old = ayah(ayah: 3, page: 2, daysAgo: 20, now: now)
        let notYet = ayah(ayah: 4, page: 2, daysAgo: nil, now: now) // never memorized
        let queue = HifzProgram.sabqiQueue([old, recentB, notYet, recentA], now: now)
        XCTAssertEqual(queue.map(\.ayah), [1, 2])  // sorted mushaf order, old + unmemorized dropped
    }

    // MARK: - Manzil rotation

    func testManzilExcludesRecentMaterial() {
        let now = Date()
        let recent = ayah(ayah: 1, page: 5, daysAgo: 2, now: now)   // in Sabqi window
        let longTerm = ayah(ayah: 2, page: 50, daysAgo: 30, now: now)
        let queue = HifzProgram.manzilQueue([recent, longTerm], cursor: 0, now: now)
        XCTAssertEqual(queue.map(\.page), [50])
    }

    func testManzilRotatesThroughPagesAndWraps() {
        let now = Date()
        let a = ayah(ayah: 1, page: 10, daysAgo: 30, now: now)
        let b = ayah(ayah: 2, page: 20, daysAgo: 30, now: now)
        let c = ayah(ayah: 3, page: 30, daysAgo: 30, now: now)
        let all = [a, b, c]  // 3 pages → 1 page/day
        XCTAssertEqual(HifzProgram.manzilQueue(all, cursor: 0, now: now).map(\.page), [10])
        XCTAssertEqual(HifzProgram.manzilQueue(all, cursor: 1, now: now).map(\.page), [20])
        XCTAssertEqual(HifzProgram.manzilQueue(all, cursor: 2, now: now).map(\.page), [30])
        XCTAssertEqual(HifzProgram.manzilQueue(all, cursor: 3, now: now).map(\.page), [10]) // wrap
    }

    func testAdvanceCursorWrapsModuloPageCount() {
        XCTAssertEqual(HifzProgram.advanceCursor(cursor: 0, memorizedPageCount: 3), 1)
        XCTAssertEqual(HifzProgram.advanceCursor(cursor: 2, memorizedPageCount: 3), 0)
        XCTAssertEqual(HifzProgram.advanceCursor(cursor: 5, memorizedPageCount: 0), 0) // no pages
    }

    func testCycleLengthScalesWithVolume() {
        XCTAssertEqual(HifzProgram.recommendedCycleDays(memorizedPages: 10), 7)
        XCTAssertEqual(HifzProgram.recommendedCycleDays(memorizedPages: 60), 15)
        XCTAssertEqual(HifzProgram.recommendedCycleDays(memorizedPages: 300), 30)
    }

    func testPagesPerDayCoversWholeHifzWithinCycle() {
        XCTAssertEqual(HifzProgram.pagesPerDay(memorizedPages: 0), 0)
        XCTAssertGreaterThanOrEqual(HifzProgram.pagesPerDay(memorizedPages: 7), 1)
        // 300 pages over a 30-day cycle → 10 pages/day.
        XCTAssertEqual(HifzProgram.pagesPerDay(memorizedPages: 300), 10)
    }

    // MARK: - Weak links

    func testWeakLinksSurfaceRepeatedlyMissedMemorizedAyahsWorstFirst() {
        let now = Date()
        let clean = ayah(ayah: 1, page: 1, daysAgo: 3, now: now, mistakes: 0)
        let shaky = ayah(ayah: 2, page: 1, daysAgo: 3, now: now, mistakes: 4)
        let worst = ayah(ayah: 3, page: 1, daysAgo: 3, now: now, mistakes: 9)
        let notMemorized = ayah(ayah: 4, page: 1, daysAgo: nil, now: now, mistakes: 7)
        let weak = HifzProgram.weakLinks([clean, shaky, worst, notMemorized], threshold: 3)
        XCTAssertEqual(weak.map(\.ayah), [3, 2])  // worst first; clean + unmemorized excluded
    }
}
