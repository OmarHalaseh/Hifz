import XCTest
@testable import Hifz

final class EngineTests: XCTestCase {

    private let cal = Calendar(identifier: .gregorian)
    private lazy var now = cal.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))

    // MARK: - SM-2

    func testFirstGoodReviewSchedulesOneDay() {
        let state = SpacedRepetition.initialState(now: now, calendar: cal)
        let next = SpacedRepetition.schedule(state, rating: .good, now: now, calendar: cal)
        XCTAssertEqual(next.intervalDays, 1)
        XCTAssertEqual(next.repetitions, 1)
        XCTAssertEqual(next.dueDate, cal.date(byAdding: .day, value: 1, to: now))
    }

    func testIntervalGrowsOnSuccessiveGoodReviews() {
        var state = SpacedRepetition.initialState(now: now, calendar: cal)
        state = SpacedRepetition.schedule(state, rating: .good, now: now, calendar: cal) // -> 1 day
        state = SpacedRepetition.schedule(state, rating: .good, now: now, calendar: cal) // -> 6 days
        XCTAssertEqual(state.intervalDays, 6)
        let before = state.intervalDays
        state = SpacedRepetition.schedule(state, rating: .good, now: now, calendar: cal) // -> 6 * ease
        XCTAssertGreaterThan(state.intervalDays, before)
    }

    func testAgainResetsInterval() {
        var state = SpacedRepetition.initialState(now: now, calendar: cal)
        state = SpacedRepetition.schedule(state, rating: .easy, now: now, calendar: cal)
        state = SpacedRepetition.schedule(state, rating: .easy, now: now, calendar: cal)
        state = SpacedRepetition.schedule(state, rating: .again, now: now, calendar: cal)
        XCTAssertEqual(state.intervalDays, 1)
        XCTAssertEqual(state.repetitions, 0)
    }

    func testEaseNeverDropsBelowFloor() {
        var state = SpacedRepetition.initialState(now: now, calendar: cal)
        for _ in 0..<10 {
            state = SpacedRepetition.schedule(state, rating: .again, now: now, calendar: cal)
        }
        XCTAssertGreaterThanOrEqual(state.easeFactor, SpacedRepetition.minimumEase)
    }

    // MARK: - Streak

    func testStreakCountsConsecutiveDays() {
        let logs = (0..<3).map { offset -> ReviewLog in
            let day = cal.date(byAdding: .day, value: -offset, to: now)!
            return ReviewLog(date: day, unitKey: "surah-1", rating: .good, intervalAfter: 1)
        }
        XCTAssertEqual(ProgressManager.streak(from: logs, now: now, calendar: cal), 3)
    }

    func testStreakBreaksOnGap() {
        let today = ReviewLog(date: now, unitKey: "surah-1", rating: .good, intervalAfter: 1)
        let threeDaysAgo = ReviewLog(date: cal.date(byAdding: .day, value: -3, to: now)!,
                                     unitKey: "surah-2", rating: .good, intervalAfter: 1)
        XCTAssertEqual(ProgressManager.streak(from: [today, threeDaysAgo], now: now, calendar: cal), 1)
    }

    // MARK: - Scheduler

    func testSpacedRepetitionSurfacesOnlyDueMemorizedUnits() {
        let due = MemorizationProgress(unitKey: "surah-1", granularity: .surah, surahNumber: 1, status: .memorized)
        due.dueDate = cal.date(byAdding: .day, value: -1, to: now) // overdue

        let notDue = MemorizationProgress(unitKey: "surah-2", granularity: .surah, surahNumber: 2, status: .memorized)
        notDue.dueDate = cal.date(byAdding: .day, value: 5, to: now) // future

        let learning = MemorizationProgress(unitKey: "surah-3", granularity: .surah, surahNumber: 3, status: .learning)

        let result = RevisionScheduler.dueItems(
            [due, notDue, learning], mode: .spacedRepetition, granularity: .surah, now: now, calendar: cal
        )
        XCTAssertEqual(result.map(\.unitKey), ["surah-1"])
    }

    func testSelfRatedOrdersByWeakestFirst() {
        let strong = MemorizationProgress(unitKey: "surah-1", granularity: .surah, surahNumber: 1, status: .memorized)
        strong.strength = 0.9
        let weak = MemorizationProgress(unitKey: "surah-2", granularity: .surah, surahNumber: 2, status: .memorized)
        weak.strength = 0.2

        let result = RevisionScheduler.dueItems(
            [strong, weak], mode: .selfRated, granularity: .surah, now: now, calendar: cal
        )
        XCTAssertEqual(result.map(\.unitKey), ["surah-2", "surah-1"])
    }

    // MARK: - Data integrity

    func testAllSurahsLoadWithCorrectTotals() {
        XCTAssertEqual(QuranData.surahs.count, 114)
        XCTAssertEqual(QuranData.surahs.map(\.ayahCount).reduce(0, +), 6236)
        XCTAssertEqual(QuranData.surahs.first?.transliteration, "Al-Fatihah")
        XCTAssertEqual(QuranData.surahs.last?.number, 114)
    }
}
