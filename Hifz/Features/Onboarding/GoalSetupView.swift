import SwiftUI
import SwiftData

/// Asks the user how many new ayahs they want to memorize each day, and previews
/// how long that pace takes to finish the whole Quran. Shown on first launch and
/// reachable again from the dashboard / settings.
struct GoalSetupView: View {
    @Bindable var settings: AppSettings
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var allProgress: [MemorizationProgress]

    /// Local draft so nothing persists until the user confirms.
    @State private var perDay: Int

    private static let presets = [1, 3, 5, 10]

    init(settings: AppSettings) {
        self.settings = settings
        _perDay = State(initialValue: max(1, settings.dailyNewAyahs))
    }

    /// Forecast of finishing from *zero* at the drafted pace — a stable "how big is
    /// this commitment" preview, independent of current progress.
    private var previewDays: Int {
        Int((Double(QuranData.totalAyahs) / Double(max(1, perDay))).rounded(.up))
    }

    private var previewDuration: String {
        Self.humanDuration(days: previewDays)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header

                    VStack(spacing: 12) {
                        ForEach(Self.presets, id: \.self) { value in
                            presetRow(value)
                        }
                        customRow
                    }

                    projectionCard
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Your daily goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.fontWeight(.semibold)
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "target")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            Text("How much do you want to memorize each day?")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Text("Pick a pace you can keep up. You can change it anytime.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    private func presetRow(_ value: Int) -> some View {
        let selected = perDay == value
        return Button {
            withAnimation(.snappy) { perDay = value }
        } label: {
            HStack {
                Text("\(value) \(value == 1 ? "ayah" : "ayahs") a day")
                    .font(.headline)
                Spacer()
                Text(Self.humanDuration(days: Int((Double(QuranData.totalAyahs) / Double(value)).rounded(.up))))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(selected ? AnyShapeStyle(Color.accentColor.opacity(0.12)) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(selected ? Color.accentColor : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var customRow: some View {
        HStack {
            Text("Custom")
                .font(.headline)
            Spacer()
            Stepper("\(perDay)", value: $perDay, in: 1...100)
                .labelsHidden()
            Text("\(perDay)/day")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 52, alignment: .trailing)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemGroupedBackground)))
    }

    private var projectionCard: some View {
        VStack(spacing: 6) {
            Text("At \(perDay) \(perDay == 1 ? "ayah" : "ayahs") a day")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("You'd memorize the whole Quran in about")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(previewDuration)
                .font(.system(.title, design: .rounded).weight(.bold))
                .foregroundStyle(.tint)
                .contentTransition(.numericText())
                .animation(.snappy, value: previewDays)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemGroupedBackground)))
    }

    private func save() {
        settings.dailyNewAyahs = perDay
        settings.hasSetGoal = true
        try? context.save()
        dismiss()
    }

    /// Renders a day count as an approximate "X years, Y months" / "Z days" string.
    static func humanDuration(days: Int) -> String {
        guard days > 0 else { return "no time" }
        if days < 45 { return "\(days) day\(days == 1 ? "" : "s")" }
        let years = days / 365
        let months = (days % 365) / 30
        if years == 0 {
            let m = max(1, months)
            return "\(m) month\(m == 1 ? "" : "s")"
        }
        if months == 0 { return "\(years) year\(years == 1 ? "" : "s")" }
        return "\(years) yr \(months) mo"
    }
}
