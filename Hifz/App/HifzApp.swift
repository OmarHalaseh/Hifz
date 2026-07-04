import SwiftUI
import SwiftData

@main
struct HifzApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(
                for: Schema.current,
                migrationPlan: HifzMigrationPlan.self
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        // Ensure a settings row exists on first launch.
        _ = AppSettings.current(in: container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
