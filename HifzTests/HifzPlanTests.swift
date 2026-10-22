import XCTest
import SwiftData
@testable import Hifz

/// Revision blocks (whole short surahs, page parts of long ones), the ḥifẓ plan
/// projections, and un-marking memorized units.
final class HifzPlanTests: XCTestCase {

    private let cal = Calendar.current
    private let now = Date()

    private func daysAgo(_ d: Int) -> Date { cal.date(byAdding: .day, value: -d, to: now)! }

    private func snap(_ surah: Int, _ ayah: Int, page: Int, memorizedDaysAgo: Int = 30,
                      reviewedDaysAgo: Int? = nil, interval: Int = 0) -> HifzPageScheduler.AyahSnapshot {
        .init(surah: surah, ayah: ayah, page: page, memorizedAt: daysAgo(memorizedDaysAgo),
              lastReviewedAt: reviewedDaysAgo.map(daysAgo), intervalDays: interval)
    }

    // MARK: - Revision blocks

    /// A short surah straddling a page break stays one block — never half a surah.
    func testShortSurahAcrossPageBreakIsOneBlock() {
        let ayahs = (1...10).map { snap(80, $0, page: $0 <= 5 ? 585 : 586) }
        let blocks = HifzPageScheduler.revisionBlocks(from: ayahs, lineCost: { _, _ in 2 }, now: now)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].ayahKeys.count, 10)
        XCTAssertTrue(blocks[0].isWholeSurah)
    }

    /// A long surah is split per page, and a sliver at the end folds into its neighbour.
    func testLongSurahSplitsByPageAndFoldsSlivers() {
        // 3 full pages of 15 lines (5 ayahs × 3 lines), then a 2-line sliver page.
        var ayahs: [HifzPageScheduler.AyahSnapshot] = []
        for i in 1...15 { ayahs.append(snap(2, i, page: 2 + (i - 1) / 5)) }
        ayahs.append(snap(2, 16, page: 5))
        let blocks = HifzPageScheduler.revisionBlocks(
            from: ayahs, lineCost: { _, a in a == 16 ? 2 : 3 }, now: now)
        XCTAssertEqual(blocks.map(\.partCount), [3, 3, 3])
        XCTAssertEqual(blocks.last?.lastAyah, 16)
        XCTAssertEqual(blocks.map(\.lines), [15, 15, 17])
    }

    /// Ayahs still inside the Sabqi week don't enter Manzil.
    func testRecentAyahsStayOutOfManzil() {
        let ayahs = [snap(114, 1, page: 604, memorizedDaysAgo: 2)]
        XCTAssertTrue(HifzPageScheduler.revisionBlocks(from: ayahs, lineCost: { _, _ in 1 }, now: now).isEmpty)
    }

    /// The most overdue block comes first and the budget is respected.
    func testBlockQueueTakesMostOverdueWithinBudget() {
        let ayahs = [
            snap(112, 1, page: 604, reviewedDaysAgo: 10, interval: 6),   // 4 days overdue
            snap(113, 1, page: 604, reviewedDaysAgo: 20, interval: 6),   // 14 days overdue
            snap(114, 1, page: 604, reviewedDaysAgo: 1, interval: 6),    // not due
        ]
        let blocks = HifzPageScheduler.revisionBlocks(from: ayahs, lineCost: { _, _ in 10 }, now: now)
        let queue = HifzPageScheduler.blockQueue(blocks, lineBudget: 15, now: now)
        XCTAssertEqual(queue.map(\.surah), [113])
    }

    // MARK: - Plan

    /// Lessons are laid out one portion per day, and a surah's date range spans
    /// every day it takes.
    func testSabaqScheduleDatesEachSurah() {
        // Surah 114: 6 ayahs × 1 line; surah 113: 5 ayahs × 1 line; 5 lines/day.
        let unlearned = (1...6).map { (surah: 114, ayah: $0) } + (1...5).map { (surah: 113, ayah: $0) }
        let plan = HifzPlan.sabaqSchedule(unlearned: unlearned, lines: 5, start: now,
                                          lineCost: { _, _ in 1 })
        XCTAssertEqual(plan.map(\.surah), [114, 113])
        XCTAssertEqual(plan[0].startDay, 0)
        XCTAssertEqual(plan[0].endDay, 1)          // ayah 6 spills into day 2
        XCTAssertEqual(plan[1].startDay, 1)
        XCTAssertEqual(plan[1].endDay, 2)
        XCTAssertEqual(plan[1].days, 2)
    }

    /// Every block shows up in the forecast within the 30-day cap, and a block
    /// revised in the forecast isn't repeated the next day.
    func testRevisionForecastCoversEveryBlock() {
        let ayahs = (78...114).map { snap($0, 1, page: 600) }
        let days = HifzPlan.revisionForecast(ayahs: ayahs, days: 30, now: now, lineCost: { _, _ in 3 })
        let seen = Set(days.flatMap { $0.blocks.map(\.surah) })
        XCTAssertEqual(seen, Set(78...114))
        XCTAssertTrue(Set(days[0].blocks.map(\.surah)).isDisjoint(with: days[1].blocks.map(\.surah)))
    }

    // MARK: - Un-marking

    private func inMemoryContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema.current, migrationPlan: HifzMigrationPlan.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    /// Un-marking a surah removes its ayahs from the ḥifẓ and clears its mark.
    func testUnmarkRemovesSurahFromHifz() throws {
        let context = try inMemoryContext()
        let unit = QuranData.units(for: .surah).first { $0.surahNumber == 114 }!
        let progress = ProgressManager.progress(for: unit, existing: [], in: context)
        ProgressManager.setStatus(.memorized, for: progress)
        let rows = HifzProgramManager.seedMemorized(units: [unit], existing: [], in: context)
        XCTAssertEqual(rows.count, 6)

        HifzProgramManager.unmark(units: [unit], existing: rows, progress: [progress], in: context)
        try context.save()

        XCTAssertTrue(try context.fetch(FetchDescriptor<HifzAyah>()).isEmpty)
        XCTAssertEqual(progress.status, .notStarted)
        XCTAssertTrue(MemorizationCoverage.manuallyMemorizedAyahKeys(from: [progress]).isEmpty)
    }

    /// Un-marking one surah inside a memorized juz keeps the juz's other surahs.
    func testUnmarkInsideMemorizedJuzKeepsNeighbours() throws {
        let context = try inMemoryContext()
        let juz = QuranData.units(for: .juz).first { $0.juzNumber == 30 }!
        let juzProgress = ProgressManager.progress(for: juz, existing: [], in: context)
        ProgressManager.setStatus(.memorized, for: juzProgress)
        let surah = QuranData.units(for: .surah).first { $0.surahNumber == 114 }!

        HifzProgramManager.unmark(units: [surah], existing: [], progress: [juzProgress], in: context)
        try context.save()

        let left = try context.fetch(FetchDescriptor<HifzAyah>())
        let keys = Set(left.filter(\.isMemorized).map(\.key))
        XCTAssertFalse(keys.contains("114:1"))
        XCTAssertTrue(keys.contains("113:1"))
        XCTAssertTrue(keys.contains("78:1"))
        XCTAssertEqual(juzProgress.status, .learning)
    }
}
