import XCTest
import SwiftData
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

    // MARK: - Manual memorization bridges into Sabaq

    /// A surah marked memorized manually expands to all its ayah keys; units that
    /// aren't `.memorized` contribute nothing.
    func testManuallyMemorizedKeysExpandOnlyMemorizedUnits() {
        let done = MemorizationProgress(
            unitKey: MemorizationProgress.surahKey(114),
            granularity: .surah, surahNumber: 114, status: .memorized
        )
        let learning = MemorizationProgress(
            unitKey: MemorizationProgress.surahKey(113),
            granularity: .surah, surahNumber: 113, status: .learning
        )
        let keys = MemorizationCoverage.manuallyMemorizedAyahKeys(from: [done, learning])

        // An-Nās (114) has 6 ayahs; Al-Falaq (113, only "learning") contributes none.
        XCTAssertEqual(keys.count, 6)
        XCTAssertTrue(keys.contains(HifzAyah.makeKey(surah: 114, ayah: 1)))
        XCTAssertTrue(keys.contains(HifzAyah.makeKey(surah: 114, ayah: 6)))
        XCTAssertFalse(keys.contains(HifzAyah.makeKey(surah: 113, ayah: 1)))
    }

    /// Regression: a surah marked memorized from the surah list (a
    /// `MemorizationProgress` row, no `HifzAyah` rows) must not be re-offered as a
    /// new Sabaq lesson.
    func testSabaqSkipsSurahMarkedMemorizedViaProgressRow() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Schema.current, migrationPlan: HifzMigrationPlan.self, configurations: config
        )
        let context = ModelContext(container)

        // Mark An-Nās (114) memorized the "old" way — no HifzAyah rows exist for it.
        context.insert(MemorizationProgress(
            unitKey: MemorizationProgress.surahKey(114),
            granularity: .surah, surahNumber: 114, status: .memorized
        ))
        let state = HifzProgramState()
        context.insert(state)

        let rows = HifzProgramManager.ensureTodaysSabaq(
            state: state, existing: [],
            manuallyMemorizedKeys: MemorizationCoverage.manuallyMemorizedAyahKeys(
                from: try context.fetch(FetchDescriptor<MemorizationProgress>())
            ),
            settings: AppSettings(), recentAccuracy: 1, fromEnd: true,
            in: context, now: now, calendar: cal
        )

        // From-the-end would normally start at An-Nās; it's already memorized, so the
        // lesson must skip it and begin at the next surah (Al-Falaq, 113).
        XCTAssertFalse(rows.isEmpty)
        XCTAssertTrue(rows.allSatisfy { $0.surah != 114 })
        XCTAssertEqual(rows.first?.surah, 113)
    }

    /// Marking a surah memorized seeds per-ayah rows dated outside the Sabqi window,
    /// so it enters the Manzil rotation directly rather than this week's daily
    /// recitation — and re-seeding is a no-op.
    func testSeedMemorizedEntersManzilNotSabqi() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Schema.current, migrationPlan: HifzMigrationPlan.self, configurations: config
        )
        let context = ModelContext(container)

        let anNas = TrackUnit(
            key: MemorizationProgress.surahKey(114), granularity: .surah,
            title: "", subtitle: "", arabic: nil,
            surahNumber: 114, pageNumber: 0, juzNumber: 0, ayahFrom: 0, ayahTo: 0
        )

        let created = HifzProgramManager.seedMemorized(
            units: [anNas], existing: [], in: context, now: now, calendar: cal
        )

        // An-Nās has 6 ayahs, all seeded as memorized Manzil rows.
        XCTAssertEqual(created.count, 6)
        XCTAssertTrue(created.allSatisfy { $0.isMemorized && $0.phase == .manzil })

        // Dated before the 7-day cutoff → excluded from the daily Sabqi recitation…
        XCTAssertTrue(HifzProgram.sabqiQueue(created, now: now, calendar: cal).isEmpty)

        // …and, once its page is fully covered, the page derives to the Manzil tier.
        let states = HifzPageScheduler.pageStates(
            from: created,
            lineCountOnPage: { _ in 15 },
            ayahKeysOnPage: { _ in created.map(\.key) },
            now: now, calendar: cal
        )
        XCTAssertEqual(states.map(\.tier), [.manzil])

        // Idempotent: re-seeding with the rows already present adds nothing.
        let again = HifzProgramManager.seedMemorized(
            units: [anNas], existing: created, in: context, now: now, calendar: cal
        )
        XCTAssertTrue(again.isEmpty)
    }

    // MARK: - Data integrity

    func testAllSurahsLoadWithCorrectTotals() {
        XCTAssertEqual(QuranData.surahs.count, 114)
        XCTAssertEqual(QuranData.surahs.map(\.ayahCount).reduce(0, +), 6236)
        XCTAssertEqual(QuranData.surahs.first?.transliteration, "Al-Fatihah")
        XCTAssertEqual(QuranData.surahs.last?.number, 114)
    }
}
