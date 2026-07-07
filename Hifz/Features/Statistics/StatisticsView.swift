import SwiftUI
import SwiftData
import Charts

struct StatisticsView: View {
    @Environment(\.modelContext) private var context
    @Query private var allProgress: [MemorizationProgress]
    @Query private var allLogs: [ReviewLog]
    @Query private var settingsList: [AppSettings]
    @Query private var hifzAyahs: [HifzAyah]

    private var settings: AppSettings { settingsList.first ?? AppSettings.current(in: context) }
    private var granularity: Granularity { settings.granularity }
    private var memorizedKeys: Set<String> { MemorizationCoverage.memorizedKeys(from: hifzAyahs) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    statusSection
                    reviewsSection
                    cumulativeSection
                    heatmapSection
                }
                .padding()
            }
            .navigationTitle("Statistics")
            .background(Color(.systemGroupedBackground))
        }
    }

    // MARK: - Status breakdown

    private var statusCounts: [(status: MemorizationStatus, count: Int)] {
        // Unified: the ḥifẓ program's ayah coverage and manual marks both count.
        let c = MemorizationCoverage.statusCounts(
            units: QuranData.units(for: granularity),
            memorizedKeys: memorizedKeys,
            stored: MemorizationCoverage.storedStatus(from: allProgress, granularity: granularity)
        )
        return [
            (.memorized, c.memorized),
            (.learning, c.learning),
            (.notStarted, c.notStarted),
        ]
    }

    private var statusSection: some View {
        card("Progress by \(granularity.shortLabel)") {
            Chart(statusCounts, id: \.status) { item in
                SectorMark(
                    angle: .value("Count", item.count),
                    innerRadius: .ratio(0.6),
                    angularInset: 2
                )
                .foregroundStyle(item.status.color)
                .cornerRadius(4)
            }
            .frame(height: 180)
            HStack(spacing: 16) {
                ForEach(statusCounts, id: \.status) { item in
                    HStack(spacing: 6) {
                        Circle().fill(item.status.color).frame(width: 8, height: 8)
                        Text("\(item.status.label): \(item.count)").font(.caption)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Reviews per day (last 30 days)

    private struct DayCount: Identifiable { let id = UUID(); let day: Date; let count: Int }

    private var reviewsPerDay: [DayCount] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let byDay = Dictionary(grouping: allLogs) { cal.startOfDay(for: $0.date) }
        return (0..<30).reversed().compactMap { offset in
            guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return DayCount(day: day, count: byDay[day]?.count ?? 0)
        }
    }

    private var reviewsSection: some View {
        card("Reviews · last 30 days") {
            if allLogs.isEmpty {
                emptyChart("No reviews logged yet")
            } else {
                Chart(reviewsPerDay) { item in
                    BarMark(
                        x: .value("Day", item.day, unit: .day),
                        y: .value("Reviews", item.count)
                    )
                    .foregroundStyle(Color.accentColor.gradient)
                }
                .frame(height: 160)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 7)) { value in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
            }
        }
    }

    // MARK: - Cumulative memorized over time

    private struct CumPoint: Identifiable { let id = UUID(); let date: Date; let total: Int }

    /// Cumulative *ayahs* memorized over time, unioning the program's per-ayah
    /// timestamps with manual unit marks (each ayah counted once, at the earliest
    /// date it was memorized either way).
    private var cumulativeMemorized: [CumPoint] {
        var firstMemorized: [String: Date] = [:]
        for ayah in hifzAyahs {
            guard let date = ayah.memorizedAt else { continue }
            firstMemorized[ayah.key] = min(firstMemorized[ayah.key] ?? date, date)
        }
        for progress in allProgress where progress.status == .memorized {
            guard let date = progress.memorizedAt else { continue }
            for key in MemorizationCoverage.ayahKeys(in: QuranData.unit(for: progress)) {
                firstMemorized[key] = min(firstMemorized[key] ?? date, date)
            }
        }
        let dates = firstMemorized.values.sorted()
        guard !dates.isEmpty else { return [] }
        var running = 0
        return dates.map { date in
            running += 1
            return CumPoint(date: date, total: running)
        }
    }

    private var cumulativeSection: some View {
        card("Ayahs memorized over time") {
            if cumulativeMemorized.isEmpty {
                emptyChart("Memorize ayahs to see your growth")
            } else {
                Chart(cumulativeMemorized) { point in
                    LineMark(x: .value("Date", point.date), y: .value("Total", point.total))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(Color.green)
                    AreaMark(x: .value("Date", point.date), y: .value("Total", point.total))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(Color.green.opacity(0.15))
                }
                .frame(height: 160)
            }
        }
    }

    // MARK: - Activity heatmap (last 12 weeks)

    private var heatmapSection: some View {
        card("Activity") {
            let cal = Calendar.current
            let today = cal.startOfDay(for: .now)
            let byDay = Dictionary(grouping: allLogs) { cal.startOfDay(for: $0.date) }
            let weeks = 12
            let columns = Array(repeating: GridItem(.fixed(16), spacing: 4), count: weeks)

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(0..<(weeks * 7), id: \.self) { i in
                    let offset = (weeks * 7 - 1) - i
                    let day = cal.date(byAdding: .day, value: -offset, to: today) ?? today
                    let count = byDay[cal.startOfDay(for: day)]?.count ?? 0
                    RoundedRectangle(cornerRadius: 3)
                        .fill(heatColor(count))
                        .frame(width: 16, height: 16)
                }
            }
            HStack(spacing: 6) {
                Text("Less").font(.caption2).foregroundStyle(.secondary)
                ForEach(0..<4) { level in
                    RoundedRectangle(cornerRadius: 2).fill(heatColor(level * 2)).frame(width: 12, height: 12)
                }
                Text("More").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func heatColor(_ count: Int) -> Color {
        switch count {
        case 0: return Color.secondary.opacity(0.12)
        case 1...2: return Color.accentColor.opacity(0.35)
        case 3...5: return Color.accentColor.opacity(0.6)
        default: return Color.accentColor
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 18))
    }

    private func emptyChart(_ message: String) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 120)
    }
}
