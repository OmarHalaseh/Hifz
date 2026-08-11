import XCTest
import SwiftData
@testable import Hifz

/// Guards the versioned-schema scaffolding (A0). These tests are cheap insurance:
/// they fail loudly the moment a model change slips in without a matching schema
/// version + migration stage.
final class SchemaMigrationTests: XCTestCase {

    func testMigrationPlanChainsAllVersions() {
        // V1 stays pinned as the base shape (never mutated).
        XCTAssertEqual(SchemaV1.versionIdentifier, Schema.Version(1, 0, 0))
        XCTAssertEqual(SchemaV1.models.count, 3)

        // V2 adds the ayah-atomic Sabaq/Sabqi/Manzil models on top of V1.
        XCTAssertEqual(SchemaV2.versionIdentifier, Schema.Version(2, 0, 0))
        XCTAssertEqual(SchemaV2.models.count, 6)

        // V3 keeps the same model set but adds line-range attributes to
        // MemorizationProgress (half/quarter/row granularities).
        XCTAssertEqual(SchemaV3.versionIdentifier, Schema.Version(3, 0, 0))
        XCTAssertEqual(SchemaV3.models.count, 6)

        // V4 adds the daily-lesson-size attribute (sabaqUnit) to AppSettings.
        XCTAssertEqual(SchemaV4.versionIdentifier, Schema.Version(4, 0, 0))
        XCTAssertEqual(SchemaV4.models.count, 6)

        // V5 removes manzilCursor from HifzProgramState — the first removal.
        XCTAssertEqual(SchemaV5.versionIdentifier, Schema.Version(5, 0, 0))
        XCTAssertEqual(SchemaV5.models.count, 6)

        // The plan chains V1 → V2 → V3 → V4 → V5, each a lightweight stage.
        XCTAssertEqual(HifzMigrationPlan.schemas.count, 5)
        XCTAssertEqual(HifzMigrationPlan.stages.count, 4)
    }

    /// Every version must describe a *distinct* shape. When they don't — as was the
    /// case until 2026-08-11, with every version returning the live model types —
    /// SwiftData aborts any real migration with "Duplicate version checksums
    /// detected" and the app can no longer open its store.
    func testEverySchemaVersionHasADistinctShape() {
        let versions: [any VersionedSchema.Type] = HifzMigrationPlan.schemas
        for (i, lhs) in versions.enumerated() {
            for rhs in versions[(i + 1)...] {
                let a = lhs.models.map(ObjectIdentifier.init)
                let b = rhs.models.map(ObjectIdentifier.init)
                XCTAssertNotEqual(
                    a, b,
                    "\(lhs.versionIdentifier) and \(rhs.versionIdentifier) list the same model types, "
                    + "so they describe the same shape and will collide on migration"
                )
            }
        }
    }

    /// The test that would have caught the duplicate-checksum defect: an **on-disk**
    /// store written at V4 and reopened under the current schema. In-memory stores
    /// never migrate, so no amount of in-memory testing exercises the plan.
    func testOnDiskStoreMigratesFromV4ToCurrent() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("migration-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }

        // Write a store stamped V4 — the shape shipped before manzilCursor was cut.
        do {
            let old = try ModelContainer(
                for: Schema(versionedSchema: SchemaV4.self),
                configurations: ModelConfiguration(url: url)
            )
            let context = ModelContext(old)
            let state = SchemaV2.HifzProgramState()
            state.manzilCursor = 17
            state.sabaqKeys = ["114:1"]
            context.insert(state)

            let progress = SchemaV3.MemorizationProgress()
            progress.unitKey = MemorizationProgress.surahKey(114)
            progress.status = .memorized
            context.insert(progress)
            try context.save()
        }

        // Reopen it under the live schema; the plan must carry it to V5.
        let migrated = try ModelContainer(
            for: Schema.current, migrationPlan: HifzMigrationPlan.self,
            configurations: ModelConfiguration(url: url)
        )
        let context = ModelContext(migrated)

        let state = try XCTUnwrap(try context.fetch(FetchDescriptor<HifzProgramState>()).first)
        XCTAssertEqual(state.sabaqKeys, ["114:1"], "surviving attributes keep their values")

        let progress = try XCTUnwrap(try context.fetch(FetchDescriptor<MemorizationProgress>()).first)
        XCTAssertEqual(progress.unitKey, MemorizationProgress.surahKey(114))
        XCTAssertEqual(progress.status, .memorized)
    }

    /// The full chain, from the original shipping shape to today's.
    func testOnDiskStoreMigratesFromV1ToCurrent() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("migration-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            let old = try ModelContainer(
                for: Schema(versionedSchema: SchemaV1.self),
                configurations: ModelConfiguration(url: url)
            )
            let context = ModelContext(old)
            let progress = SchemaV1.MemorizationProgress()
            progress.unitKey = MemorizationProgress.surahKey(1)
            progress.status = .memorized
            context.insert(progress)
            try context.save()
        }

        let migrated = try ModelContainer(
            for: Schema.current, migrationPlan: HifzMigrationPlan.self,
            configurations: ModelConfiguration(url: url)
        )
        let context = ModelContext(migrated)

        let progress = try XCTUnwrap(try context.fetch(FetchDescriptor<MemorizationProgress>()).first)
        XCTAssertEqual(progress.unitKey, MemorizationProgress.surahKey(1))
        XCTAssertEqual(progress.status, .memorized)
        XCTAssertEqual(progress.lineFrom, 0, "attributes added along the way take their defaults")
    }

    func testVersionedContainerBuildsAndPersists() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Schema.current,
            migrationPlan: HifzMigrationPlan.self,
            configurations: config
        )
        let context = ModelContext(container)

        context.insert(MemorizationProgress(
            unitKey: MemorizationProgress.surahKey(1),
            granularity: .surah, surahNumber: 1, status: .memorized
        ))
        context.insert(ReviewLog(unitKey: "surah-1", rating: .good, intervalAfter: 1))
        context.insert(AppSettings())
        try context.save()

        XCTAssertEqual(try context.fetch(FetchDescriptor<MemorizationProgress>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ReviewLog>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<AppSettings>()).count, 1)
    }

    /// The unique constraint on `unitKey` is load-bearing today but is the exact
    /// thing that must change before CloudKit (P6). This documents the current
    /// behavior so that a future removal is a deliberate, tested decision.
    func testUnitKeyUniquenessUpsertsRatherThanDuplicates() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Schema.current, migrationPlan: HifzMigrationPlan.self, configurations: config
        )
        let context = ModelContext(container)

        let key = MemorizationProgress.surahKey(2)
        context.insert(MemorizationProgress(unitKey: key, granularity: .surah, surahNumber: 2))
        context.insert(MemorizationProgress(unitKey: key, granularity: .surah, surahNumber: 2))
        try context.save()

        let rows = try context.fetch(FetchDescriptor<MemorizationProgress>())
        XCTAssertEqual(rows.count, 1, "unitKey is @Attribute(.unique): inserts upsert on the key.")
    }
}
