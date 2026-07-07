import SwiftUI
import SwiftData

/// Asks the user how much they want to memorize each day — as a number of ayahs
/// or as a mushaf unit (quarter / half / whole page) — and previews how long that
/// pace takes to finish the whole Quran. Shown on first launch and reachable again
/// from the dashboard / settings.
struct GoalSetupView: View {
    @Bindable var settings: AppSettings
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// A daily pace, expressed the way the user thinks about it.
    private enum GoalChoice: Hashable {
        case ayahs(Int)
        case unit(MushafUnitKind)
    }

    /// Local draft so nothing persists until the user confirms.
    @State private var choice: GoalChoice
    @State private var customAyahs: Int

    private static let ayahPresets = [1, 3, 5, 10]
    private static let unitPresets: [MushafUnitKind] = [.quarter, .half, .page]

    init(settings: AppSettings) {
        self.settings = settings
        let ayahs = max(1, settings.dailyNewAyahs)
        // Prefer showing the mushaf unit when it matches the saved ayah pace, so
        // this screen and Settings › New lesson size stay in agreement.
        if HifzProgram.ayahCount(forLines: settings.sabaqUnit.baseLines) == ayahs,
           Self.unitPresets.contains(settings.sabaqUnit) {
            _choice = State(initialValue: .unit(settings.sabaqUnit))
        } else {
            _choice = State(initialValue: .ayahs(ayahs))
        }
        _customAyahs = State(initialValue: ayahs)
    }

    /// The drafted pace in ayahs/day — drives the forecast and the saved goal.
    private var perDay: Int { ayahsPerDay(for: choice) }

    private func ayahsPerDay(for choice: GoalChoice) -> Int {
        switch choice {
        case .ayahs(let n): return max(1, n)
        case .unit(let u):  return HifzProgram.ayahCount(forLines: u.baseLines)
        }
    }

    /// Forecast of finishing from *zero* at the drafted pace — a stable "how big is
    /// this commitment" preview, independent of current progress.
    private var previewDays: Int {
        Int((Double(QuranData.totalAyahs) / Double(max(1, perDay))).rounded(.up))
    }

    private var previewDuration: String { Self.humanDuration(days: previewDays) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header

                    VStack(spacing: 12) {
                        ForEach(Self.ayahPresets, id: \.self) { value in
                            choiceRow(title: "\(value) \(value == 1 ? "ayah" : "ayahs") a day",
                                      choice: .ayahs(value))
                        }

                        Divider().padding(.vertical, 2)

                        ForEach(Self.unitPresets) { unit in
                            choiceRow(title: "\(unit.label) a day", choice: .unit(unit))
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

    private func choiceRow(title: String, choice rowChoice: GoalChoice) -> some View {
        let selected = choice == rowChoice
        let days = Int((Double(QuranData.totalAyahs) / Double(max(1, ayahsPerDay(for: rowChoice)))).rounded(.up))
        return Button {
            withAnimation(.snappy) { choice = rowChoice }
        } label: {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Text(Self.humanDuration(days: days))
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
        let selected: Bool = {
            if case .ayahs(let n) = choice { return !Self.ayahPresets.contains(n) }
            return false
        }()
        return HStack {
            Text("Custom")
                .font(.headline)
            Spacer()
            Stepper(
                "\(customAyahs)",
                value: Binding(get: { customAyahs },
                               set: { customAyahs = $0; choice = .ayahs($0) }),
                in: 1...100
            )
            .labelsHidden()
            Text("\(customAyahs) ayahs/day")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 92, alignment: .trailing)
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

    private var paceLabel: String {
        switch choice {
        case .ayahs(let n): return "At \(n) \(n == 1 ? "ayah" : "ayahs") a day"
        case .unit(let u):  return "At \(u.label.lowercased()) a day (~\(perDay) ayahs)"
        }
    }

    private var projectionCard: some View {
        VStack(spacing: 6) {
            Text(paceLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
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
        switch choice {
        case .unit(let u):
            settings.sabaqUnit = u
        case .ayahs:
            // Keep the program's Sabaq size in step with the chosen ayah pace.
            settings.sabaqUnit = Self.closestUnit(toAyahs: perDay)
        }
        settings.hasSetGoal = true
        try? context.save()
        dismiss()
    }

    /// The mushaf unit whose daily portion is nearest a given ayah pace.
    private static func closestUnit(toAyahs ayahs: Int) -> MushafUnitKind {
        MushafUnitKind.allCases.min {
            abs(HifzProgram.ayahCount(forLines: $0.baseLines) - ayahs)
                < abs(HifzProgram.ayahCount(forLines: $1.baseLines) - ayahs)
        } ?? .quarter
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
