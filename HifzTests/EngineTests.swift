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

    // MARK: - Sabaq ordering

    private let sabaqAtoms: [(surah: Int, ayah: Int, page: Int, juz: Int)] = [
        (1, 1, 1, 1), (1, 2, 1, 1),          // Al-Fātiḥa
        (2, 1, 2, 1), (2, 2, 2, 1),          // Al-Baqara
        (114, 1, 604, 30), (114, 2, 604, 30) // An-Nās
    ]

    func testSabaqDefaultsToMushafOrder() {
        let picked = HifzProgram.nextSabaqAtoms(
            orderedAtoms: sabaqAtoms, memorizedOrInProgressKeys: [], count: 2
        )
        XCTAssertEqual(picked.map(\.surah), [1, 1])
        XCTAssertEqual(picked.map(\.ayah), [1, 2])
    }

    func testSabaqFromEndStartsAtLastSurah() {
        let picked = HifzProgram.nextSabaqAtoms(
            orderedAtoms: sabaqAtoms, memorizedOrInProgressKeys: [], count: 2, fromEnd: true
        )
        // An-Nās first, and ayahs within the surah stay ascending.
        XCTAssertEqual(picked.map(\.surah), [114, 114])
        XCTAssertEqual(picked.map(\.ayah), [1, 2])
    }

    func testSabaqFromEndSkipsInProgressAndCrossesSurahBoundary() {
        let taken: Set<String> = [
            HifzAyah.makeKey(surah: 114, ayah: 1),
            HifzAyah.makeKey(surah: 114, ayah: 2)
        ]
        let picked = HifzProgram.nextSabaqAtoms(
            orderedAtoms: sabaqAtoms, memorizedOrInProgressKeys: taken, count: 2, fromEnd: true
        )
        // An-Nās is done → next surah from the end is Al-Baqara, ayahs ascending.
        XCTAssertEqual(picked.map(\.surah), [2, 2])
        XCTAssertEqual(picked.map(\.ayah), [1, 2])
    }

    // MARK: - Data integrity

    func testAllSurahsLoadWithCorrectTotals() {
        XCTAssertEqual(QuranData.surahs.count, 114)
        XCTAssertEqual(QuranData.surahs.map(\.ayahCount).reduce(0, +), 6236)
        XCTAssertEqual(QuranData.surahs.first?.transliteration, "Al-Fatihah")
        XCTAssertEqual(QuranData.surahs.last?.number, 114)
    }
}
