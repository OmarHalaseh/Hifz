import XCTest
import SwiftData
@testable import Hifz

/// Guards the versioned-schema scaffolding (A0). These tests are cheap insurance:
/// they fail loudly the moment a model change slips in without a matching schema
/// version + migration stage.
final class SchemaMigrationTests: XCTestCase {

    func testMigrationPlanShapeIsV1Only() {
        XCTAssertEqual(SchemaV1.versionIdentifier, Schema.Version(1, 0, 0))
        XCTAssertEqual(SchemaV1.models.count, 3)
        XCTAssertEqual(HifzMigrationPlan.schemas.count, 1)
        XCTAssertTrue(
            HifzMigrationPlan.stages.isEmpty,
            "V1 is the base schema and must have no migration stages."
        )
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
