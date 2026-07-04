import Foundation
import SwiftData

/// Versioned schema for the SwiftData store.
///
/// `SchemaV1` pins the current, shipping model shape. All future model changes
/// must add a new `SchemaVn` **and** a `MigrationStage` in `HifzMigrationPlan`
/// rather than mutating this one — that keeps migrations explicit and testable
/// instead of relying on implicit lightweight inference.
enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [MemorizationProgress.self, ReviewLog.self, AppSettings.self]
    }
}

/// The migration plan the app's `ModelContainer` runs on launch.
///
/// One schema, no stages yet: this is scaffolding so that when the model changes
/// (e.g. adding Sabaq/Sabqi/Manzil buckets), we append `SchemaV2` + a stage here
/// and cover it with a migration test — never edit `SchemaV1` in place.
enum HifzMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}

extension Schema {
    /// The current live schema, built from the latest versioned schema.
    static var current: Schema { Schema(versionedSchema: SchemaV1.self) }
}
