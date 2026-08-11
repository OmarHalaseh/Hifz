import XCTest
import SwiftData
@testable import Hifz

/// Tests for the on-device JSON backup — the app's only safety net, since nothing
/// is synced anywhere. A backup that silently drops a field is worse than none.
final class BackupArchiveTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema.current, migrationPlan: HifzMigrationPlan.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    /// Populates a store with one row of every kind, each field set to a value
    /// distinguishable from its default so a dropped field can't pass unnoticed.
    private func populate(_ context: ModelContext, now: Date) {
        let settings = AppSettings()
        settings.granularity = .page
        settings.revisionMode = .selfRated
        settings.remindersEnabled = true
        settings.reminderHour = 6
        settings.reminderMinute = 45
        settings.dailyGoal = 12
        settings.dailyNewAyahs = 9
        settings.sabaqUnit = .half
        settings.hasSetGoal = true
        settings.memorizeReminderEnabled = true
        settings.memorizeReminderHour = 5
        settings.memorizeReminderMinute = 30
        context.insert(settings)

        let state = HifzProgramState(
            manzilCursor: 17, sabqiClearedOn: now, sabaqAssignedOn: now,
            sabaqKeys: ["114:1", "114:2"], sabaqConfirmedKeys: ["114:1"]
        )
        context.insert(state)

        let progress = MemorizationProgress(
            unitKey: "quarter-604-2", granularity: .quarterPage,
            surahNumber: 114, pageNumber: 604, juzNumber: 30,
            ayahFrom: 1, ayahTo: 6, lineFrom: 4, lineTo: 7, status: .memorized
        )
        progress.strength = 0.75
        progress.easeFactor = 2.9
        progress.intervalDays = 21
        progress.repetitions = 4
        progress.dueDate = now
        progress.lastReviewedAt = now
        progress.memorizedAt = now
        context.insert(progress)

        let ayah = HifzAyah(surah: 114, ayah: 1, page: 604, juz: 30, phase: .manzil)
        ayah.memorizedAt = now
        ayah.lastReviewedAt = now
        ayah.mistakeCount = 3
        ayah.easeFactor = 2.1
        ayah.intervalDays = 14
        ayah.repetitions = 6
        ayah.dueDate = now
        context.insert(ayah)

        context.insert(ReviewLog(date: now, unitKey: "114:1", rating: .easy, intervalAfter: 14))
        context.insert(MistakeLog(date: now, ayahKey: "114:1", kind: "stuck"))
    }

    /// Capture → JSON → decode → restore into an empty store must reproduce every
    /// value, not just the row counts.
    func testRoundTripThroughJSONPreservesEveryField() throws {
        let now = Date(timeIntervalSince1970: 1_770_000_000)  // whole second: ISO-8601 safe
        let source = try makeContext()
        populate(source, now: now)
        try source.save()

        let data = try BackupArchive.capture(from: source).encoded()
        let restored = try makeContext()
        try BackupArchive.decoded(from: data).restore(into: restored)

        let settings = try XCTUnwrap(try restored.fetch(FetchDescriptor<AppSettings>()).first)
        XCTAssertEqual(settings.granularity, .page)
        XCTAssertEqual(settings.revisionMode, .selfRated)
        XCTAssertTrue(settings.remindersEnabled)
        XCTAssertEqual(settings.reminderHour, 6)
        XCTAssertEqual(settings.reminderMinute, 45)
        XCTAssertEqual(settings.dailyGoal, 12)
        XCTAssertEqual(settings.dailyNewAyahs, 9)
        XCTAssertEqual(settings.sabaqUnit, .half)
        XCTAssertTrue(settings.hasSetGoal)
        XCTAssertTrue(settings.memorizeReminderEnabled)
        XCTAssertEqual(settings.memorizeReminderHour, 5)
        XCTAssertEqual(settings.memorizeReminderMinute, 30)

        let state = try XCTUnwrap(try restored.fetch(FetchDescriptor<HifzProgramState>()).first)
        XCTAssertEqual(state.manzilCursor, 17)
        XCTAssertEqual(state.sabqiClearedOn, now)
        XCTAssertEqual(state.sabaqAssignedOn, now)
        XCTAssertEqual(state.sabaqKeys, ["114:1", "114:2"])
        XCTAssertEqual(state.sabaqConfirmedKeys, ["114:1"])

        let progress = try XCTUnwrap(try restored.fetch(FetchDescriptor<MemorizationProgress>()).first)
        XCTAssertEqual(progress.unitKey, "quarter-604-2")
        XCTAssertEqual(progress.granularity, .quarterPage)
        XCTAssertEqual(progress.status, .memorized)
        XCTAssertEqual(progress.surahNumber, 114)
        XCTAssertEqual(progress.pageNumber, 604)
        XCTAssertEqual(progress.juzNumber, 30)
        XCTAssertEqual(progress.ayahFrom, 1)
        XCTAssertEqual(progress.ayahTo, 6)
        XCTAssertEqual(progress.lineFrom, 4)
        XCTAssertEqual(progress.lineTo, 7)
        XCTAssertEqual(progress.strength, 0.75)
        XCTAssertEqual(progress.easeFactor, 2.9)
        XCTAssertEqual(progress.intervalDays, 21)
        XCTAssertEqual(progress.repetitions, 4)
        XCTAssertEqual(progress.dueDate, now)
        XCTAssertEqual(progress.lastReviewedAt, now)
        XCTAssertEqual(progress.memorizedAt, now)

        let ayah = try XCTUnwrap(try restored.fetch(FetchDescriptor<HifzAyah>()).first)
        XCTAssertEqual(ayah.key, "114:1")
        XCTAssertEqual(ayah.page, 604)
        XCTAssertEqual(ayah.juz, 30)
        XCTAssertEqual(ayah.phase, .manzil)
        XCTAssertEqual(ayah.memorizedAt, now)
        XCTAssertEqual(ayah.lastReviewedAt, now)
        XCTAssertEqual(ayah.mistakeCount, 3)
        XCTAssertEqual(ayah.easeFactor, 2.1)
        XCTAssertEqual(ayah.intervalDays, 14)
        XCTAssertEqual(ayah.repetitions, 6)
        XCTAssertEqual(ayah.dueDate, now)

        let review = try XCTUnwrap(try restored.fetch(FetchDescriptor<ReviewLog>()).first)
        XCTAssertEqual(review.date, now)
        XCTAssertEqual(review.unitKey, "114:1")
        XCTAssertEqual(review.rating, .easy)
        XCTAssertEqual(review.intervalAfter, 14)

        let mistake = try XCTUnwrap(try restored.fetch(FetchDescriptor<MistakeLog>()).first)
        XCTAssertEqual(mistake.date, now)
        XCTAssertEqual(mistake.ayahKey, "114:1")
        XCTAssertEqual(mistake.kind, "stuck")
    }

    /// A restore replaces rather than merges — restoring twice must not leave two
    /// copies of every review, and must not resurrect data the archive doesn't have.
    func testRestoreReplacesInsteadOfMerging() throws {
        let now = Date(timeIntervalSince1970: 1_770_000_000)
        let source = try makeContext()
        populate(source, now: now)
        let data = try BackupArchive.capture(from: source).encoded()

        let target = try makeContext()
        // Pre-existing data that the archive knows nothing about.
        target.insert(HifzAyah(surah: 2, ayah: 255, page: 42, juz: 3))
        target.insert(ReviewLog(date: now, unitKey: "2:255", rating: .again, intervalAfter: 1))
        try target.save()

        try BackupArchive.decoded(from: data).restore(into: target)
        try BackupArchive.decoded(from: data).restore(into: target)

        XCTAssertEqual(try target.fetch(FetchDescriptor<ReviewLog>()).count, 1)
        XCTAssertEqual(try target.fetch(FetchDescriptor<AppSettings>()).count, 1)
        XCTAssertEqual(try target.fetch(FetchDescriptor<HifzProgramState>()).count, 1)
        let ayahs = try target.fetch(FetchDescriptor<HifzAyah>())
        XCTAssertEqual(ayahs.map(\.key), ["114:1"], "Ayat al-Kursi wasn't in the archive")
    }

    /// An empty store round-trips to an empty archive rather than failing.
    func testEmptyStoreProducesRestorableArchive() throws {
        let data = try BackupArchive.capture(from: try makeContext()).encoded()
        let archive = try BackupArchive.decoded(from: data)
        XCTAssertTrue(archive.ayahs.isEmpty)
        XCTAssertNil(archive.settings)
        XCTAssertNoThrow(try archive.restore(into: try makeContext()))
    }

    /// Anything that isn't a Hifz archive must be reported, not crash or half-apply.
    func testGarbageFileIsRejected() {
        XCTAssertThrowsError(try BackupArchive.decoded(from: Data("not json".utf8)))

        // The dangerous case: because every section is optional, valid JSON with no
        // Hifz content would otherwise decode to an *empty* archive — and restoring
        // that would silently wipe the store. `format` is what tells them apart.
        XCTAssertThrowsError(
            try BackupArchive.decoded(from: Data(#"{"hello":"world"}"#.utf8))
        ) { error in
            guard case BackupError.unreadable = error else {
                return XCTFail("expected .unreadable, got \(error)")
            }
        }

        XCTAssertThrowsError(try BackupArchive.decoded(from: Data(#"{"format":999}"#.utf8))) { error in
            guard case BackupError.tooNew = error else {
                return XCTFail("expected .tooNew, got \(error)")
            }
        }
    }

    /// An archive written by an older build — only the keys that existed then —
    /// still restores, filling everything else with defaults.
    func testArchiveMissingOptionalSectionsStillRestores() throws {
        let json = #"{"format":1,"ayahs":[{"surah":114,"ayah":1}]}"#
        let archive = try BackupArchive.decoded(from: Data(json.utf8))
        let context = try makeContext()
        try archive.restore(into: context)

        let ayah = try XCTUnwrap(try context.fetch(FetchDescriptor<HifzAyah>()).first)
        XCTAssertEqual(ayah.key, "114:1")
        XCTAssertEqual(ayah.phase, .sabaq)      // defaulted
        XCTAssertEqual(ayah.easeFactor, 2.5)    // defaulted
        XCTAssertNil(ayah.memorizedAt)
    }

    /// The filename carries the export date so successive backups don't overwrite.
    func testSuggestedFilenameIsDated() {
        var archive = BackupArchive()
        archive.exportedAt = Date(timeIntervalSince1970: 1_770_000_000)
        XCTAssertTrue(archive.suggestedFilename.hasPrefix("Hifz-Backup-2026-"),
                      "got \(archive.suggestedFilename)")
    }
}
