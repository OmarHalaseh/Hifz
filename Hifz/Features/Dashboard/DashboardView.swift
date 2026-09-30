import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var context
    @Query private var allProgress: [MemorizationProgress]
    @Query private var allLogs: [ReviewLog]
    @Query private var settingsList: [AppSettings]
    @Query private var hifzAyahs: [HifzAyah]
    @Query private var hifzStateList: [HifzProgramState]

    /// Jumps the app to the Ḥifẓ tab (injected by `RootView`).
    var onOpenHifz: () -> Void = {}

    @State private var showGoalSheet = false

    private var settings: AppSettings { settingsList.first ?? AppSettings.current(in: context) }

    private var granularity: Granularity { settings.granularity }
    private var forecast: MemorizationForecast {
        MemorizationForecast.compute(program: hifzAyahs, progress: allProgress, settings: settings)
    }
    private var totalUnits: Int { QuranData.units(for: granularity).count }

    /// Unified counts: a unit is memorized if the program has all its ayahs
    /// memorized or it was marked manually (see `MemorizationCoverage`).
    private var coverage: (memorized: Int, learning: Int, notStarted: Int) {
        MemorizationCoverage.statusCounts(
            units: QuranData.units(for: granularity),
            memorizedKeys: MemorizationCoverage.memorizedKeys(from: hifzAyahs),
            stored: MemorizationCoverage.storedStatus(from: allProgress, granularity: granularity)
        )
    }
    private var memorizedCount: Int { coverage.memorized }
    private var learningCount: Int { coverage.learning }
    private var fraction: Double {
        totalUnits == 0 ? 0 : Double(memorizedCount) / Double(totalUnits)
    }
    /// Today's long-term revision load: due Manzil pages under the 30-day cap.
    private var manzilDuePages: [HifzPageScheduler.PageState] {
        HifzPageScheduler.todaysManzilPages(from: hifzAyahs)
    }
    private var streak: Int { ProgressManager.streak(from: allLogs) }
    private var reviewsToday: Int {
        let today = Calendar.current.startOfDay(for: .now)
        return allLogs.filter { Calendar.current.startOfDay(for: $0.date) == today }.count
    }

    // MARK: - Ḥifẓ program (Sabaq / Sabqi / Manzil)

    private var sabqiDue: Int { HifzProgram.sabqiQueue(hifzAyahs).count }
    private var sabaqUnlocked: Bool {
        HifzProgram.isSabaqUnlocked(sabqiCount: sabqiDue, sabqiClearedOn: hifzStateList.first?.sabqiClearedOn)
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

                    hifzCard

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

    /// Manzil call-to-action: today's due long-term pages (30-day cap). Tapping
    /// jumps to the Ḥifẓ tab, where the Manzil session lives.
    @ViewBuilder
    private var reviseCard: some View {
        let due = manzilDuePages.count
        Button(action: onOpenHifz) {
            HStack(spacing: 14) {
                Image(systemName: due == 0 ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath")
                    .font(.title)
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 2) {
                    Text(due == 0 ? "Manzil caught up" : "Manzil · \(due) page\(due == 1 ? "" : "s")")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(due == 0 ? "No long-term pages due today" : "Today's long-term revision — tap to start")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.8))
            }
            .padding()
            .background(
                LinearGradient(colors: due == 0 ? [.green, .teal] : [.accentColor, .indigo],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 18)
            )
        }
        .buttonStyle(.plain)
        .disabled(due == 0)
    }

    /// Today's ḥifẓ call-to-action: Sabqi comes first (it blocks new Sabaq), else
    /// prompt today's new lesson. Tapping jumps to the Ḥifẓ tab.
    @ViewBuilder
    private var hifzCard: some View {
        let showSabqi = sabqiDue > 0
        Button(action: onOpenHifz) {
            HStack(spacing: 14) {
                Image(systemName: showSabqi ? "clock.arrow.circlepath" : "sparkles")
                    .font(.title)
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 2) {
                    Text(showSabqi ? "Sabqi · \(sabqiDue) to recite" : "Sabaq · New lesson")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(showSabqi
                         ? "Recite recent memorization, then unlock a new lesson."
                         : (sabaqUnlocked ? "Start today's portion — quality over speed."
                                          : "Clear today's Sabqi to unlock a new lesson."))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.8))
            }
            .padding()
            .background(
                LinearGradient(colors: showSabqi ? [.orange, .pink] : [.purple, .indigo],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 18)
            )
        }
        .buttonStyle(.plain)
    }
}
