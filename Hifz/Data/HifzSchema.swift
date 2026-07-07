import Foundation
import SwiftData

/// Versioned schema for the SwiftData store.
///
/// `SchemaV1` pins the original shipping model shape and must never be mutated.
/// Model changes add a new `SchemaVn` **and** a `MigrationStage` in
/// `HifzMigrationPlan`, covered by a migration test — keeping migrations explicit
/// and testable instead of relying on implicit lightweight inference.
enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [MemorizationProgress.self, ReviewLog.self, AppSettings.self]
    }
}

/// V2 adds the ayah-atomic Sabaq/Sabqi/Manzil program models alongside the
/// existing ones. Purely additive → a lightweight migration.
enum SchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [MemorizationProgress.self, ReviewLog.self, AppSettings.self,
         HifzAyah.self, MistakeLog.self, HifzProgramState.self]
    }
}

/// V3 adds mushaf line-range tracking (`lineFrom`/`lineTo`) to
/// `MemorizationProgress` for the half-page, quarter-page, and row granularities.
/// The new attributes are non-optional with a `0` default → lightweight migration.
enum SchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [MemorizationProgress.self, ReviewLog.self, AppSettings.self,
         HifzAyah.self, MistakeLog.self, HifzProgramState.self]
    }
}

/// The migration plan the app's `ModelContainer` runs on launch.
enum HifzMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self, SchemaV3.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2, migrateV2toV3]
    }

    /// V1 → V2 only introduces new model types; existing rows are untouched.
    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: SchemaV1.self,
        toVersion: SchemaV2.self
    )

    /// V2 → V3 adds defaulted line-range attributes to `MemorizationProgress`.
    static let migrateV2toV3 = MigrationStage.lightweight(
        fromVersion: SchemaV2.self,
        toVersion: SchemaV3.self
    )
}

extension Schema {
    /// The current live schema, built from the latest versioned schema.
    static var current: Schema { Schema(versionedSchema: SchemaV3.self) }
}
