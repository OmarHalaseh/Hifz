import SwiftUI
import SwiftData

/// The app's top-level tabs. Tagged so views (e.g. the Today dashboard) can jump
/// programmatically to the Ḥifẓ tab.
enum RootTab: Hashable {
    case today, surahs, hifz, stats, settings
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query private var settingsList: [AppSettings]

    @State private var selection: RootTab = .today

    private var settings: AppSettings { settingsList.first ?? AppSettings.current(in: context) }

    var body: some View {
        TabView(selection: $selection) {
            DashboardView(onOpenHifz: { selection = .hifz })
                .tabItem { Label("Today", systemImage: "house.fill") }
                .tag(RootTab.today)

            SurahListView()
                .tabItem { Label("Surahs", systemImage: "book.closed.fill") }
                .tag(RootTab.surahs)

            HifzHomeView()
                .tabItem { Label("Ḥifẓ", systemImage: "brain.head.profile") }
                .tag(RootTab.hifz)

            StatisticsView()
                .tabItem { Label("Stats", systemImage: "chart.bar.fill") }
                .tag(RootTab.stats)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(RootTab.settings)
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
        .modelContainer(for: [MemorizationProgress.self, ReviewLog.self, AppSettings.self,
                              HifzAyah.self, MistakeLog.self, HifzProgramState.self], inMemory: true)
}
