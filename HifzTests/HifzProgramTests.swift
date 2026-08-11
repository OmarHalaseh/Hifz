import XCTest
import SwiftData
@testable import Hifz

/// Unit tests for the pure `HifzProgram` decision logic (Sabaq / Sabqi / Manzil).
/// Everything here is store-free — `HifzAyah` rows are built in memory — except
/// where a call has to log to the store (`confirmFlawless`), which uses an
/// in-memory container.
final class HifzProgramTests: XCTestCase {

    private let cal = Calendar.current

    /// A throwaway in-memory store for the few calls that write log rows.
    private func inMemoryContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema.current, migrationPlan: HifzMigrationPlan.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

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

    /// The portion is measured in *printed lines*, so how many ayahs fit depends on
    /// how long they are — six third-of-a-line ayahs make the same two lines that a
    /// single long ayah would.
    func testSabaqPortionFillsTheLineBudgetWithHoweverManyAyahsItTakes() {
        let short: [(surah: Int, ayah: Int, page: Int, juz: Int)] =
            (1...6).map { (surah: 114, ayah: $0, page: 604, juz: 30) }
        let long: [(surah: Int, ayah: Int, page: Int, juz: Int)] =
            [(surah: 2, ayah: 282, page: 48, juz: 3)]
        let cost: (Int, Int) -> Double = { surah, _ in surah == 114 ? 1.0 / 3 : 4 }

        let picked = HifzProgram.nextSabaqAtoms(
            orderedAtoms: short + long, memorizedOrInProgressKeys: [], lines: 2, lineCost: cost
        )
        XCTAssertEqual(picked.count, 6)                      // 6 × ⅓ line = 2 lines exactly
        XCTAssertTrue(picked.allSatisfy { $0.surah == 114 })  // the 4-line ayah would overshoot
    }

    /// An ayah longer than the whole daily portion (2:282 spans a page) still has to
    /// be offered — otherwise the lesson would be empty and ḥifẓ would stall.
    func testSabaqPortionPicksAtLeastOneAyahEvenWhenItOvershoots() {
        let picked = HifzProgram.nextSabaqAtoms(
            orderedAtoms: [(surah: 2, ayah: 282, page: 48, juz: 3)],
            memorizedOrInProgressKeys: [], lines: 1, lineCost: { _, _ in 15 }
        )
        XCTAssertEqual(picked.count, 1)
    }

    /// The regression this replaced: sizing the portion from the mushaf-wide average
    /// produced the *same* ayah count everywhere, so a "quarter page" of Juzʼ ʻAmma
    /// was far less than a quarter page while one of Al-Baqara was far more. Measured
    /// against the real layout, both cover about a quarter page — with different
    /// numbers of ayahs.
    func testQuarterPagePortionIsConstantPageAreaNotConstantAyahCount() {
        let lines = MushafUnitKind.quarter.baseLines
        let atoms = HifzText.orderedAtomTuples
        let fatiha = Set((1...7).map { HifzAyah.makeKey(surah: 1, ayah: $0) })

        // From the end → starts at An-Nās; from the front (Al-Fātiḥa done) → Al-Baqara.
        let juzAmma = HifzProgram.nextSabaqAtoms(
            orderedAtoms: atoms, memorizedOrInProgressKeys: [], lines: lines, fromEnd: true
        )
        let baqara = HifzProgram.nextSabaqAtoms(
            orderedAtoms: atoms, memorizedOrInProgressKeys: fatiha, lines: lines
        )
        XCTAssertEqual(juzAmma.first?.surah, 114)
        XCTAssertEqual(baqara.first?.surah, 2)

        func printedLines(_ p: [(surah: Int, ayah: Int, page: Int, juz: Int)]) -> Double {
            p.reduce(0) { $0 + MushafLayout.lineCost(surah: $1.surah, ayah: $1.ayah) }
        }
        XCTAssertEqual(printedLines(juzAmma), Double(lines), accuracy: 2)
        XCTAssertEqual(printedLines(baqara), Double(lines), accuracy: 2)
        XCTAssertNotEqual(juzAmma.count, baqara.count,
                          "a quarter page is a different number of ayahs in each place")
    }

    /// Every ayah printed on a page must account for exactly that page's text lines,
    /// so line costs can be summed into a portion size without drift.
    func testAyahLineCostsOnAPageSumToItsTextLineCount() {
        for page in [1, 2, 255, 604] {
            let keys = Set(MushafLayout.textLines(onPage: page).flatMap(\.segments).map {
                HifzAyah.makeKey(surah: $0.surah, ayah: $0.ayah)
            })
            // Only ayahs printed *entirely* on this page contribute their whole cost;
            // ones spilling across the page break contribute part of it elsewhere.
            let total = keys.reduce(0.0) { sum, key in
                let parts = key.split(separator: ":").compactMap { Int($0) }
                return sum + MushafLayout.lineCost(surah: parts[0], ayah: parts[1])
            }
            // Tolerance for the accumulated per-segment division; the sum can land
            // a few ulps below the whole line count.
            XCTAssertGreaterThanOrEqual(total + 1e-9,
                                        Double(MushafLayout.textLines(onPage: page).count),
                                        "page \(page)")
        }
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

    func testSabqiQueueFromEndReversesSurahOrderButKeepsAyahsAscending() {
        let now = Date()
        // Two surahs memorized recently; expect from-end to list the later surah first.
        let s2a1 = ayah(surah: 2, ayah: 1, page: 2, daysAgo: 1, now: now)
        let s2a2 = ayah(surah: 2, ayah: 2, page: 2, daysAgo: 1, now: now)
        let s114a1 = ayah(surah: 114, ayah: 1, page: 604, daysAgo: 1, now: now)
        let s114a2 = ayah(surah: 114, ayah: 2, page: 604, daysAgo: 1, now: now)
        let queue = HifzProgram.sabqiQueue([s2a1, s114a2, s2a2, s114a1], now: now, fromEnd: true)
        // Surahs descending (114 before 2); ayahs within a surah stay ascending.
        XCTAssertEqual(queue.map { [$0.surah, $0.ayah] }, [[114, 1], [114, 2], [2, 1], [2, 2]])
    }

    func testSabqiQueueExcludesAyahsAlreadyDueInFuture() {
        let now = Date()
        let start = cal.startOfDay(for: now)
        // Memorized recently but reviewed today → next due tomorrow.
        let doneToday = ayah(ayah: 1, page: 1, daysAgo: 1, now: now)
        doneToday.dueDate = cal.date(byAdding: .day, value: 1, to: start)
        // Memorized recently, due today.
        let dueNow = ayah(ayah: 2, page: 1, daysAgo: 1, now: now)
        dueNow.dueDate = start
        let queue = HifzProgram.sabqiQueue([doneToday, dueNow], now: now)
        XCTAssertEqual(queue.map(\.ayah), [2])   // the future-due one is filtered out
    }

    /// The reported bug: a Sabaq lesson confirmed today must not reappear as a
    /// due Sabqi the same day; it stamps a review today and schedules the next
    /// one for tomorrow, so it only returns on its scheduled day.
    func testConfirmedSabaqIsNotDueSabqiSameDayButReturnsNextDay() throws {
        let now = Date()
        let state = HifzProgramState()
        let a = HifzAyah(surah: 114, ayah: 1, page: 604, juz: 30)
        HifzProgramManager.confirmFlawless(a, state: state, in: try inMemoryContext(), now: now)

        XCTAssertTrue(a.isMemorized)
        XCTAssertEqual(a.phase, .sabqi)
        XCTAssertNotNil(a.lastReviewedAt)                 // reviewed today
        XCTAssertEqual(a.dueDate, cal.date(byAdding: .day, value: 1,
                                           to: cal.startOfDay(for: now)))  // due tomorrow

        // Not fällig today…
        XCTAssertTrue(HifzProgram.sabqiQueue([a], now: now, calendar: cal).isEmpty)
        // …but back in the Sabqi queue tomorrow.
        let tomorrow = cal.date(byAdding: .day, value: 1, to: now)!
        XCTAssertEqual(HifzProgram.sabqiQueue([a], now: tomorrow, calendar: cal).map(\.ayah), [1])
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
