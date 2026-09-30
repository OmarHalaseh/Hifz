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

    /// Memorizing through the Sabaq/Sabqi/Manzil program must move the goal bar —
    /// for a program-only user the forecast used to read a flat zero.
    func testComputeCountsProgramMemorization() throws {
        try XCTSkipIf(QuranData.totalAyahs == 0, "surahs.json not available in test bundle")

        let settings = AppSettings(dailyNewAyahs: 3)
        let program = (1...5).map { memorizedAyah(surah: 114, ayah: $0, on: now) }
        let f = MemorizationForecast.compute(
            program: program, progress: [], settings: settings, now: now, calendar: cal
        )
        XCTAssertEqual(f.memorizedAyahs, 5)
    }

    /// The two tracks are unioned by ayah, so an ayah both routes cover counts once.
    func testComputeUnionsProgramAndManualWithoutDoubleCounting() throws {
        try XCTSkipIf(QuranData.totalAyahs == 0, "surahs.json not available in test bundle")

        let settings = AppSettings(granularity: .surah, dailyNewAyahs: 3)
        let fatiha = MemorizationProgress(
            unitKey: MemorizationProgress.surahKey(1), granularity: .surah,
            surahNumber: 1, status: .memorized
        )
        // 1:1 and 1:2 sit inside Al-Fātiḥa, already counted; 114:1 is new.
        let program = [
            memorizedAyah(surah: 1, ayah: 1, on: now),
            memorizedAyah(surah: 1, ayah: 2, on: now),
            memorizedAyah(surah: 114, ayah: 1, on: now),
        ]
        let f = MemorizationForecast.compute(
            program: program, progress: [fatiha], settings: settings, now: now, calendar: cal
        )
        XCTAssertEqual(f.memorizedAyahs, QuranData.surah(1)!.ayahCount + 1)
    }

    /// Progress marked at any granularity counts: switching the tracking unit in
    /// Settings must not make memorized ayahs disappear from the forecast.
    func testComputeCountsProgressMarkedAtAnyGranularity() throws {
        try XCTSkipIf(QuranData.totalAyahs == 0, "surahs.json not available in test bundle")

        let settings = AppSettings(granularity: .page, dailyNewAyahs: 5)
        let surah = MemorizationProgress(
            unitKey: MemorizationProgress.surahKey(114), granularity: .surah,
            surahNumber: 114, status: .memorized
        )
        let range = MemorizationProgress(
            unitKey: MemorizationProgress.ayahKey(surah: 2, from: 1, to: 5),
            granularity: .ayahRange, surahNumber: 2, ayahFrom: 1, ayahTo: 5, status: .memorized
        )
        let f = MemorizationForecast.compute(
            progress: [surah, range], settings: settings, now: now, calendar: cal
        )
        XCTAssertEqual(f.memorizedAyahs, QuranData.surah(114)!.ayahCount + 5)
    }

    func testRecentPaceCountsProgramAyahs() throws {
        try XCTSkipIf(QuranData.totalAyahs == 0, "surahs.json not available in test bundle")

        let settings = AppSettings(dailyNewAyahs: 3)
        let fiveDaysAgo = cal.date(byAdding: .day, value: -5, to: now)!
        let program = (1...10).map { memorizedAyah(surah: 2, ayah: $0, on: fiveDaysAgo) }
        let f = MemorizationForecast.compute(
            program: program, progress: [], settings: settings, now: now, calendar: cal
        )
        // 10 ayahs over the 5 elapsed days since the first of them.
        XCTAssertEqual(f.recentPacePerDay, 2.0, accuracy: 0.0001)
    }

    func testUnmemorizedProgramAyahsDoNotCount() throws {
        try XCTSkipIf(QuranData.totalAyahs == 0, "surahs.json not available in test bundle")

        let settings = AppSettings(dailyNewAyahs: 3)
        let pending = HifzAyah(surah: 114, ayah: 1, page: 604, juz: 30) // never confirmed
        let f = MemorizationForecast.compute(
            program: [pending], progress: [], settings: settings, now: now, calendar: cal
        )
        XCTAssertEqual(f.memorizedAyahs, 0)
        XCTAssertEqual(f.recentPacePerDay, 0)
    }

    /// When both routes cover an ayah, the earlier date is the one that counts.
    func testMemorizationDatesKeepTheEarlierSource() throws {
        try XCTSkipIf(QuranData.totalAyahs == 0, "surahs.json not available in test bundle")

        let lastWeek = cal.date(byAdding: .day, value: -7, to: now)!
        let program = [memorizedAyah(surah: 1, ayah: 1, on: lastWeek)]
        let fatiha = MemorizationProgress(
            unitKey: MemorizationProgress.surahKey(1), granularity: .surah,
            surahNumber: 1, status: .memorized
        )
        fatiha.memorizedAt = now

        let dates = MemorizationCoverage.memorizationDates(program: program, progress: [fatiha])
        XCTAssertEqual(dates["1:1"], lastWeek)
        XCTAssertEqual(dates["1:2"], now)
    }

    // MARK: - Helpers

    private func memorizedAyah(surah: Int, ayah: Int, on date: Date) -> HifzAyah {
        let a = HifzAyah(surah: surah, ayah: ayah, page: 1, juz: 1)
        a.memorizedAt = date
        return a
    }
}
