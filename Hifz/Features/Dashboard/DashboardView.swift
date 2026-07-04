import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var context
    @Query private var allProgress: [MemorizationProgress]
    @Query private var allLogs: [ReviewLog]
    @Query private var settingsList: [AppSettings]

    @State private var showGoalSheet = false

    private var settings: AppSettings { settingsList.first ?? AppSettings.current(in: context) }

    private var granularity: Granularity { settings.granularity }
    private var forecast: MemorizationForecast {
        MemorizationForecast.compute(progress: allProgress, settings: settings)
    }
    private var totalUnits: Int { QuranData.units(for: granularity).count }

    private var scoped: [MemorizationProgress] {
        allProgress.filter { $0.granularity == granularity }
    }
    private var memorizedCount: Int { scoped.filter { $0.status == .memorized }.count }
    private var learningCount: Int { scoped.filter { $0.status == .learning }.count }
    private var fraction: Double {
        totalUnits == 0 ? 0 : Double(memorizedCount) / Double(totalUnits)
    }
    private var dueItems: [MemorizationProgress] {
        RevisionScheduler.dueItems(allProgress, mode: settings.revisionMode, granularity: granularity)
    }
    private var streak: Int { ProgressManager.streak(from: allLogs) }
    private var reviewsToday: Int {
        let today = Calendar.current.startOfDay(for: .now)
        return allLogs.filter { Calendar.current.startOfDay(for: $0.date) == today }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    ProgressRing(fraction: fraction)
                        .frame(width: 200, height: 200)
                        .padding(.top, 8)

                    Text("\(memorizedCount) of \(totalUnits) \(granularity.shortLabel.lowercased())s memorized")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    reviseCard

                    GoalForecastCard(forecast: forecast) { showGoalSheet = true }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        StatCard(value: "\(memorizedCount)", label: "Memorized", systemImage: "checkmark.seal.fill", tint: .green)
                        StatCard(value: "\(learningCount)", label: "Learning", systemImage: "book.fill", tint: .orange)
                        StatCard(value: "\(streak)", label: "Day streak", systemImage: "flame.fill", tint: .pink)
                        StatCard(value: "\(reviewsToday)/\(settings.dailyGoal)", label: "Today's goal", systemImage: "target", tint: .accentColor)
                    }
                }
                .padding()
            }
            .navigationTitle("Hifz")
            .background(Color(.systemGroupedBackground))
            .sheet(isPresented: $showGoalSheet) {
                GoalSetupView(settings: settings)
            }
        }
    }

    @ViewBuilder
    private var reviseCard: some View {
        NavigationLink {
            RevisionSessionView(mode: settings.revisionMode, granularity: granularity)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: dueItems.isEmpty ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath")
                    .font(.title)
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 2) {
                    Text(dueItems.isEmpty ? "All caught up" : "\(dueItems.count) to revise")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(dueItems.isEmpty ? "Nothing due right now" : "Tap to start a revision session")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.8))
            }
            .padding()
            .background(
                LinearGradient(colors: dueItems.isEmpty ? [.green, .teal] : [.accentColor, .indigo],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 18)
            )
        }
        .buttonStyle(.plain)
        .disabled(dueItems.isEmpty)
    }
}
