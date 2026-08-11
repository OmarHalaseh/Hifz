import Foundation
import SwiftData

// MARK: - Versioned schemas
//
// Each version owns **frozen copies** of the models as they were at that version.
// This is the whole point of a `VersionedSchema`: it has to describe a shape that
// no longer exists in the live code, so it cannot reference the live classes.
//
// Until 2026-08-11 every version here returned the *live* model types, which made
// them all describe the same shape and hash to the same checksum. That stayed
// invisible while changes were additive — CoreData needed no real migration, so
// the plan was never evaluated — but the first attribute *removal* forced a
// migration, the plan was evaluated, and SwiftData aborted with "Duplicate version
// checksums detected", leaving the app unable to open its store at all.
//
// Rules for the next change:
//  1. Never edit a frozen model. Add a new `SchemaVn` with copies of the models as
//     they now are, reusing an older version's type wherever that model is
//     unchanged.
//  2. Only the newest version references the live top-level classes.
//  3. Add a `MigrationStage`, bump `Schema.current`, and cover it in
//     `SchemaMigrationTests` with an on-disk round trip — in-memory stores never
//     migrate, so they cannot catch a broken plan.

/// V1 — the original shipping shape: progress tracking, review log, settings.
enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [MemorizationProgress.self, ReviewLog.self, AppSettings.self]
    }

    @Model
    final class MemorizationProgress {
        @Attribute(.unique) var unitKey: String
        var granularity: Granularity
        var surahNumber: Int
        var pageNumber: Int
        var juzNumber: Int
        var ayahFrom: Int
        var ayahTo: Int
        var status: MemorizationStatus
        var strength: Double
        var easeFactor: Double
        var intervalDays: Int
        var repetitions: Int
        var dueDate: Date?
        var lastReviewedAt: Date?
        var createdAt: Date
        var memorizedAt: Date?

        init() {
            unitKey = ""
            granularity = .surah
            surahNumber = 0
            pageNumber = 0
            juzNumber = 0
            ayahFrom = 0
            ayahTo = 0
            status = .notStarted
            strength = 0.5
            easeFactor = 2.5
            intervalDays = 0
            repetitions = 0
            createdAt = .now
        }
    }

    @Model
    final class ReviewLog {
        var date: Date
        var unitKey: String
        var rating: ReviewRating
        var intervalAfter: Int

        init() {
            date = .now
            unitKey = ""
            rating = .good
            intervalAfter = 0
        }
    }

    @Model
    final class AppSettings {
        var granularity: Granularity
        var revisionMode: RevisionMode
        var remindersEnabled: Bool
        var reminderHour: Int
        var reminderMinute: Int
        var dailyGoal: Int
        var dailyNewAyahs: Int = 3
        var hasSetGoal: Bool = false
        var memorizeReminderEnabled: Bool = false
        var memorizeReminderHour: Int = 7
        var memorizeReminderMinute: Int = 0

        init() {
            granularity = .surah
            revisionMode = .spacedRepetition
            remindersEnabled = false
            reminderHour = 20
            reminderMinute = 0
            dailyGoal = 5
        }
    }
}

/// V2 — adds the ayah-atomic Sabaq/Sabqi/Manzil program. The three V1 models are
/// unchanged and are reused as-is.
enum SchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [SchemaV1.MemorizationProgress.self, SchemaV1.ReviewLog.self, SchemaV1.AppSettings.self,
         HifzAyah.self, MistakeLog.self, HifzProgramState.self]
    }

    @Model
    final class HifzAyah {
        @Attribute(.unique) var key: String
        var surah: Int
        var ayah: Int
        var page: Int
        var juz: Int
        var phase: HifzPhase
        var memorizedAt: Date?
        var lastReviewedAt: Date?
        var mistakeCount: Int
        var easeFactor: Double
        var intervalDays: Int
        var repetitions: Int
        var dueDate: Date?

        init() {
            key = ""
            surah = 0
            ayah = 0
            page = 0
            juz = 0
            phase = .sabaq
            mistakeCount = 0
            easeFactor = 2.5
            intervalDays = 0
            repetitions = 0
        }
    }

    @Model
    final class MistakeLog {
        var date: Date
        var ayahKey: String
        var kind: String

        init() {
            date = .now
            ayahKey = ""
            kind = "slip"
        }
    }

    /// Carries `manzilCursor`, the rotation pointer of the cursor-based Manzil
    /// cycle that `HifzPageScheduler` later replaced. Dropped again in V5.
    @Model
    final class HifzProgramState {
        var manzilCursor: Int
        var sabqiClearedOn: Date?
        var sabaqAssignedOn: Date?
        var sabaqKeys: [String]
        var sabaqConfirmedKeys: [String]

        init() {
            manzilCursor = 0
            sabaqKeys = []
            sabaqConfirmedKeys = []
        }
    }
}

/// V3 — adds the printed-line range to `MemorizationProgress` for the sub-page
/// granularities (half page / quarter page / row). Everything else is unchanged.
enum SchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [MemorizationProgress.self, SchemaV1.ReviewLog.self, SchemaV1.AppSettings.self,
         SchemaV2.HifzAyah.self, SchemaV2.MistakeLog.self, SchemaV2.HifzProgramState.self]
    }

    @Model
    final class MemorizationProgress {
        @Attribute(.unique) var unitKey: String
        var granularity: Granularity
        var surahNumber: Int
        var pageNumber: Int
        var juzNumber: Int
        var ayahFrom: Int
        var ayahTo: Int
        var lineFrom: Int = 0
        var lineTo: Int = 0
        var status: MemorizationStatus
        var strength: Double
        var easeFactor: Double
        var intervalDays: Int
        var repetitions: Int
        var dueDate: Date?
        var lastReviewedAt: Date?
        var createdAt: Date
        var memorizedAt: Date?

        init() {
            unitKey = ""
            granularity = .surah
            surahNumber = 0
            pageNumber = 0
            juzNumber = 0
            ayahFrom = 0
            ayahTo = 0
            status = .notStarted
            strength = 0.5
            easeFactor = 2.5
            intervalDays = 0
            repetitions = 0
            createdAt = .now
        }
    }
}

/// V4 — adds the daily-lesson-size attribute (`sabaqUnit`) to `AppSettings`.
enum SchemaV4: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(4, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [SchemaV3.MemorizationProgress.self, SchemaV1.ReviewLog.self, AppSettings.self,
         SchemaV2.HifzAyah.self, SchemaV2.MistakeLog.self, SchemaV2.HifzProgramState.self]
    }

    @Model
    final class AppSettings {
        var granularity: Granularity
        var revisionMode: RevisionMode
        var remindersEnabled: Bool
        var reminderHour: Int
        var reminderMinute: Int
        var dailyGoal: Int
        var dailyNewAyahs: Int = 3
        var sabaqUnit: MushafUnitKind = MushafUnitKind.quarter
        var hasSetGoal: Bool = false
        var memorizeReminderEnabled: Bool = false
        var memorizeReminderHour: Int = 7
        var memorizeReminderMinute: Int = 0

        init() {
            granularity = .surah
            revisionMode = .spacedRepetition
            remindersEnabled = false
            reminderHour = 20
            reminderMinute = 0
            dailyGoal = 5
        }
    }
}

/// V5 — drops `HifzProgramState.manzilCursor`, the pointer of the cursor-based
/// Manzil rotation that `HifzPageScheduler` replaced. This is the live shape, so
/// it is the one version that references the top-level model classes.
enum SchemaV5: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(5, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [MemorizationProgress.self, ReviewLog.self, AppSettings.self,
         HifzAyah.self, MistakeLog.self, HifzProgramState.self]
    }
}

// MARK: - Migration plan

/// The migration plan the app's `ModelContainer` runs on launch.
enum HifzMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self, SchemaV3.self, SchemaV4.self, SchemaV5.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2, migrateV2toV3, migrateV3toV4, migrateV4toV5]
    }

    /// V1 → V2 only introduces new model types; existing rows are untouched.
    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: SchemaV1.self,
        toVersion: SchemaV2.self
    )

    /// V2 → V3 adds the defaulted `lineFrom`/`lineTo` attributes to
    /// `MemorizationProgress`.
    static let migrateV2toV3 = MigrationStage.lightweight(
        fromVersion: SchemaV2.self,
        toVersion: SchemaV3.self
    )

    /// V3 → V4 adds the defaulted `sabaqUnit` attribute to `AppSettings`.
    static let migrateV3toV4 = MigrationStage.lightweight(
        fromVersion: SchemaV3.self,
        toVersion: SchemaV4.self
    )

    /// V4 → V5 removes the unread `manzilCursor` attribute from `HifzProgramState`.
    /// The first *removal* in this store's history, and the change that exposed the
    /// duplicate-checksum defect described at the top of this file.
    static let migrateV4toV5 = MigrationStage.lightweight(
        fromVersion: SchemaV4.self,
        toVersion: SchemaV5.self
    )
}

extension Schema {
    /// The current live schema, built from the latest versioned schema.
    static var current: Schema { Schema(versionedSchema: SchemaV5.self) }
}
