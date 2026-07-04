import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query private var settingsList: [AppSettings]

    private var settings: AppSettings { settingsList.first ?? AppSettings.current(in: context) }

    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Today", systemImage: "house.fill") }

            SurahListView()
                .tabItem { Label("Surahs", systemImage: "book.closed.fill") }

            RevisionQueueView()
                .tabItem { Label("Revise", systemImage: "arrow.triangle.2.circlepath") }

            StatisticsView()
                .tabItem { Label("Stats", systemImage: "chart.bar.fill") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        // First-launch goal prompt: "how much do you want to memorize?"
        .sheet(isPresented: Binding(
            get: { !settings.hasSetGoal },
            set: { _ in }
        )) {
            GoalSetupView(settings: settings)
                .interactiveDismissDisabled()
        }
    }
}

/// Shared helper for reading the (seeded) settings row inside a view.
extension View {
    func currentSettings(_ list: [AppSettings], context: ModelContext) -> AppSettings {
        list.first ?? AppSettings.current(in: context)
    }
}

#Preview {
    RootView()
        .modelContainer(for: [MemorizationProgress.self, ReviewLog.self, AppSettings.self], inMemory: true)
}
