import SwiftUI

/// Dashboard card that turns raw progress into milestones: how far to the next
/// juz and how long until the whole Quran is memorized at the user's pace.
struct GoalForecastCard: View {
    let forecast: MemorizationForecast
    /// Called when the user taps to adjust their daily goal.
    var onEditGoal: () -> Void

    private var dateFormatter: Date.FormatStyle {
        .dateTime.month(.abbreviated).day().year()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            // Ayah progress bar.
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: forecast.fraction)
                    .tint(.accentColor)
                HStack {
                    Text("\(forecast.memorizedAyahs) / \(forecast.totalAyahs) ayahs")
                    Spacer()
                    Text("\(Int((forecast.fraction * 100).rounded()))%")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if forecast.isComplete {
                completeBanner
            } else {
                milestoneRow(
                    icon: "flag.checkered",
                    tint: .orange,
                    title: forecast.nextJuz.map { "Next: Juz \($0)" } ?? "Next milestone",
                    detail: milestoneDetail
                )
                milestoneRow(
                    icon: "book.closed.fill",
                    tint: .green,
                    title: "Whole Quran",
                    detail: finishDetail
                )
            }

            if forecast.recentPacePerDay > 0 {
                paceChip
            }
        }
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 18))
    }

    private var header: some View {
        Button(action: onEditGoal) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Memorization goal")
                        .font(.headline)
                    Text("\(forecast.goalPerDay) new \(forecast.goalPerDay == 1 ? "ayah" : "ayahs") / day")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(.tint)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func milestoneRow(icon: String, tint: Color, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var milestoneDetail: String {
        guard forecast.nextJuz != nil, let days = forecast.daysToNextJuz else {
            return "Set a daily goal to see your ETA"
        }
        let when = forecast.nextJuzDate.map { " · by \($0.formatted(dateFormatter))" } ?? ""
        return "\(GoalSetupView.humanDuration(days: days)) away\(when)"
    }

    private var finishDetail: String {
        guard let days = forecast.daysToFinishAtGoal else {
            return "Set a daily goal to see your ETA"
        }
        let when = forecast.finishDateAtGoal.map { " · by \($0.formatted(dateFormatter))" } ?? ""
        return "\(GoalSetupView.humanDuration(days: days)) at your goal\(when)"
    }

    private var paceChip: some View {
        let pace = forecast.recentPacePerDay
        let paceText = String(format: "%.1f", pace)
        var trailing = ""
        if let days = forecast.daysToFinishAtRecentPace {
            trailing = " · finish in \(GoalSetupView.humanDuration(days: days))"
        }
        return Label("Recent pace: ~\(paceText)/day\(trailing)", systemImage: "speedometer")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 2)
    }

    private var completeBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title3)
                .foregroundStyle(.green)
            Text("Alhamdulillah — you've memorized the whole Quran!")
                .font(.subheadline.weight(.semibold))
        }
    }
}
