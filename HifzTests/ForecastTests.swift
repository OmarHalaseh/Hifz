import XCTest
@testable import Hifz

final class ForecastTests: XCTestCase {

    private let cal = Calendar(identifier: .gregorian)
    private lazy var now = cal.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))

    // MARK: - Forecast math (bundle-independent)

    private func makeForecast(
        total: Int = 6236,
        memorized: Int,
        goal: Int = 3,
        recentPace: Double = 0,
        nextJuz: Int? = nil,
        toNextJuz: Int = 0
    ) -> MemorizationForecast {
        MemorizationForecast(
            totalAyahs: total,
            memorizedAyahs: memorized,
            goalPerDay: goal,
            recentPacePerDay: recentPace,
            nextJuz: nextJuz,
            ayahsToNextJuz: toNextJuz,
            reference: now
        )
    }

    func testFractionAndRemaining() {
        let f = makeForecast(memorized: 3118) // exactly half
        XCTAssertEqual(f.remainingAyahs, 3118)
        XCTAssertEqual(f.fraction, 0.5, accuracy: 0.0001)
        XCTAssertFalse(f.isComplete)
    }

    func testDaysToFinishAtGoalRoundsUp() {
        let f = makeForecast(memorized: 0, goal: 3)
        // ceil(6236 / 3) == 2079
        XCTAssertEqual(f.daysToFinishAtGoal, 2079)
        XCTAssertEqual(f.finishDateAtGoal, cal.date(byAdding: .day, value: 2079, to: now))
    }

    func testCompleteState() {
        let f = makeForecast(memorized: 6236)
        XCTAssertTrue(f.isComplete)
        XCTAssertEqual(f.remainingAyahs, 0)
        XCTAssertEqual(f.daysToFinishAtGoal, 0)
    }

    func testNextJuzDaysAtGoal() {
        let f = makeForecast(memorized: 100, goal: 3, nextJuz: 1, toNextJuz: 108)
        // ceil(108 / 3) == 36
        XCTAssertEqual(f.daysToNextJuz, 36)
        XCTAssertEqual(f.nextJuzDate, cal.date(byAdding: .day, value: 36, to: now))
    }

    func testRecentPaceForecast() {
        let f = makeForecast(memorized: 6036, recentPace: 2.0) // 200 remaining
        XCTAssertEqual(f.daysToFinishAtRecentPace, 100)
        XCTAssertEqual(f.finishDateAtRecentPace, cal.date(byAdding: .day, value: 100, to: now))
    }

    func testNoRecentPaceMeansNoRecentForecast() {
        let f = makeForecast(memorized: 100, recentPace: 0)
        XCTAssertNil(f.daysToFinishAtRecentPace)
    }

    // MARK: - Ayah weighting

    func testAyahRangeWeightIsInclusive() {
        let p = MemorizationProgress(
            unitKey: MemorizationProgress.ayahKey(surah: 2, from: 1, to: 5),
            granularity: .ayahRange, surahNumber: 2, ayahFrom: 1, ayahTo: 5, status: .memorized
        )
        XCTAssertEqual(MemorizationForecast.ayahWeight(of: p), 5)
    }

    // MARK: - Duration formatting

    func testHumanDuration() {
        XCTAssertEqual(GoalSetupView.humanDuration(days: 1), "1 day")
        XCTAssertEqual(GoalSetupView.humanDuration(days: 10), "10 days")
        XCTAssertEqual(GoalSetupView.humanDuration(days: 60), "2 months")
        XCTAssertEqual(GoalSetupView.humanDuration(days: 365), "1 year")
        XCTAssertEqual(GoalSetupView.humanDuration(days: 400), "1 yr 1 mo")
    }

    // MARK: - compute() end-to-end (needs bundled surahs.json)

    func testComputeFromEmptyProgress() throws {
        try XCTSkipIf(QuranData.totalAyahs == 0, "surahs.json not available in test bundle")

        let settings = AppSettings(dailyNewAyahs: 3)
        let f = MemorizationForecast.compute(progress: [], settings: settings, now: now, calendar: cal)

        XCTAssertEqual(f.memorizedAyahs, 0)
        XCTAssertEqual(f.fraction, 0, accuracy: 0.0001)
        XCTAssertEqual(f.nextJuz, 1)
        XCTAssertEqual(f.recentPacePerDay, 0)
        // First juz is ~1/30 of the total.
        let expectedJuz = Int((Double(QuranData.totalAyahs) / 30.0).rounded())
        XCTAssertEqual(f.ayahsToNextJuz, expectedJuz)
    }

    func testComputeCountsOnlyCurrentGranularity() throws {
        try XCTSkipIf(QuranData.totalAyahs == 0, "surahs.json not available in test bundle")

        let settings = AppSettings(granularity: .ayahRange, dailyNewAyahs: 5)
        let inScope = MemorizationProgress(
            unitKey: "a", granularity: .ayahRange, surahNumber: 1, ayahFrom: 1, ayahTo: 10, status: .memorized
        )
        let outOfScope = MemorizationProgress(
            unitKey: MemorizationProgress.surahKey(1), granularity: .surah, surahNumber: 1, status: .memorized
        )
        let f = MemorizationForecast.compute(
            progress: [inScope, outOfScope], settings: settings, now: now, calendar: cal
        )
        XCTAssertEqual(f.memorizedAyahs, 10) // only the ayah-range unit counts
    }
}
