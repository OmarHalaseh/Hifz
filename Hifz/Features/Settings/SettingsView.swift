import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var settingsList: [AppSettings]

    var body: some View {
        NavigationStack {
            if let settings = settingsList.first {
                SettingsForm(settings: settings)
            } else {
                ProgressView().onAppear { _ = AppSettings.current(in: context) }
            }
        }
    }
}

private struct SettingsForm: View {
    @Bindable var settings: AppSettings
    @Environment(\.modelContext) private var context
    @Query private var allProgress: [MemorizationProgress]
    @Query private var allLogs: [ReviewLog]

    @State private var showResetConfirm = false

    /// Memorize surahs from the end of the mushaf first (An-Nās → Al-Fātiḥa).
    @AppStorage("sabaqFromEnd") private var sabaqFromEnd = true

    /// The reciter used for per-ayah qari playback.
    @AppStorage(Qari.storageKey) private var qari: Qari = .alafasy

    private var reviseReminderTime: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: settings.reminderHour, minute: settings.reminderMinute, second: 0, of: .now
                ) ?? .now
            },
            set: { newValue in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                settings.reminderHour = comps.hour ?? 20
                settings.reminderMinute = comps.minute ?? 0
                save(); rescheduleNotifications()
            }
        )
    }

    private var memorizeReminderTime: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: settings.memorizeReminderHour, minute: settings.memorizeReminderMinute, second: 0, of: .now
                ) ?? .now
            },
            set: { newValue in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                settings.memorizeReminderHour = comps.hour ?? 7
                settings.memorizeReminderMinute = comps.minute ?? 0
                save(); rescheduleNotifications()
            }
        )
    }

    private var goalFooter: String {
        let days = Int((Double(QuranData.totalAyahs) / Double(max(1, settings.dailyNewAyahs))).rounded(.up))
        let n = goalUnitsPerDay
        let names = settings.granularity.goalUnitName
        return "At \(n) \(n == 1 ? names.one : names.many) a day you'd finish the whole Quran in about \(GoalSetupView.humanDuration(days: days))."
    }

    // MARK: Daily goal expressed in the tracking unit (page / juz / ayah)

    /// The daily "new" goal shown in the current granularity's unit. The canonical
    /// pace stays `dailyNewAyahs` (drives the forecast + reminders); page/juz just
    /// convert to and from it, so no schema change is needed.
    private var goalUnitsPerDay: Int {
        guard let per = settings.granularity.ayahsPerGoalUnit else { return settings.dailyNewAyahs }
        return max(1, Int((Double(settings.dailyNewAyahs) / per).rounded()))
    }

    private var maxGoalUnits: Int {
        switch settings.granularity {
        case .page: return QuranData.totalPages
        case .juz:  return QuranData.totalJuz
        default:    return 100
        }
    }

    private var goalUnitsBinding: Binding<Int> {
        Binding(
            get: { goalUnitsPerDay },
            set: { newUnits in
                if let per = settings.granularity.ayahsPerGoalUnit {
                    settings.dailyNewAyahs = max(1, Int((Double(newUnits) * per).rounded()))
                } else {
                    settings.dailyNewAyahs = newUnits
                }
                save(); rescheduleNotifications()
            }
        )
    }

    private var goalStepperLabel: String {
        let n = goalUnitsPerDay
        let names = settings.granularity.goalUnitName
        return "\(n) new \(n == 1 ? names.one : names.many) per day"
    }

    var body: some View {
        Form {
            Section {
                Picker(selection: $settings.granularity) {
                    ForEach(Granularity.allCases) { g in
                        Label(g.label, systemImage: g.systemImage).tag(g)
                    }
                } label: {
                    Text("Track by")
                }
                .onChange(of: settings.granularity) { _, _ in save() }
            } header: {
                Text("Granularity")
            } footer: {
                Text("Choose how finely you track your memorization. Switching keeps all existing progress.")
            }

            Section {
                Picker(selection: $settings.revisionMode) {
                    ForEach(RevisionMode.allCases) { mode in
                        Label(mode.label, systemImage: mode.systemImage).tag(mode)
                    }
                } label: {
                    Text("Revision method")
                }
                .onChange(of: settings.revisionMode) { _, _ in save() }
            } header: {
                Text("Revision")
            } footer: {
                Text(settings.revisionMode.explanation)
            }

            Section {
                Picker(selection: $settings.sabaqUnit) {
                    ForEach(MushafUnitKind.allCases) { unit in
                        Text("\(unit.label) · \(unit.baseLines) \(unit.baseLines == 1 ? "line" : "lines")").tag(unit)
                    }
                } label: {
                    Text("New lesson size")
                }
                .onChange(of: settings.sabaqUnit) { _, _ in save() }

                Toggle(isOn: $sabaqFromEnd) {
                    Label("Start from the end (An-Nās first)", systemImage: "arrow.up.and.down.text.horizontal")
                }
            } header: {
                Text("Memorization")
            } footer: {
                Text("How much new material a daily Sabaq covers — a row, quarter-page, half-page, or full page. It flexes a little with your recent accuracy.\n\nStart from the end memorizes the short surahs of Juzʼ ʻAmma first and works back toward Al-Baqara; turn it off to go in mushaf order from Al-Fātiḥa.")
            }

            Section {
                Picker(selection: $qari) {
                    ForEach(Qari.allCases) { q in
                        Text(q.displayName).tag(q)
                    }
                } label: {
                    Text("Reciter")
                }
            } header: {
                Text("Recitation")
            } footer: {
                Text("The qari you'll hear when you tap “Listen to qari” on an ayah. Audio streams from everyayah.com.")
            }

            Section {
                Stepper(goalStepperLabel, value: goalUnitsBinding, in: 1...maxGoalUnits)
                Stepper("\(settings.dailyGoal) reviews per day", value: $settings.dailyGoal, in: 1...100)
                    .onChange(of: settings.dailyGoal) { _, _ in save() }
            } header: {
                Text("Daily goal")
            } footer: {
                Text(goalFooter)
            }

            Section {
                Toggle("Revision reminder", isOn: $settings.remindersEnabled)
                    .onChange(of: settings.remindersEnabled) { _, _ in save(); rescheduleNotifications() }
                if settings.remindersEnabled {
                    DatePicker("Time", selection: reviseReminderTime, displayedComponents: .hourAndMinute)
                }

                Toggle("Memorization reminder", isOn: $settings.memorizeReminderEnabled)
                    .onChange(of: settings.memorizeReminderEnabled) { _, _ in save(); rescheduleNotifications() }
                if settings.memorizeReminderEnabled {
                    DatePicker("Time", selection: memorizeReminderTime, displayedComponents: .hourAndMinute)
                }
            } header: {
                Text("Reminders")
            } footer: {
                Text("Get nudged to revise and to memorize new ayahs at your chosen times.")
            }

            BackupSection()

            CreditsSection()

            Section {
                Button(role: .destructive) {
                    showResetConfirm = true
                } label: {
                    Label("Reset all progress", systemImage: "trash")
                }
            } footer: {
                Text("All data is stored privately on your device.")
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog("Reset all progress?", isPresented: $showResetConfirm, titleVisibility: .visible) {
            Button("Delete everything", role: .destructive) {
                ProgressManager.resetAll(progress: allProgress, logs: allLogs, in: context)
                save()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes all memorization progress and review history. This cannot be undone.")
        }
    }

    private func save() { try? context.save() }

    private func rescheduleNotifications() {
        let reviseEnabled = settings.remindersEnabled
        let reviseHour = settings.reminderHour
        let reviseMinute = settings.reminderMinute
        let memEnabled = settings.memorizeReminderEnabled
        let memHour = settings.memorizeReminderHour
        let memMinute = settings.memorizeReminderMinute
        let dailyAyahs = settings.dailyNewAyahs
        Task {
            await NotificationManager.shared.updateDailyReminder(
                enabled: reviseEnabled, hour: reviseHour, minute: reviseMinute
            )
            await NotificationManager.shared.updateMemorizationReminder(
                enabled: memEnabled, hour: memHour, minute: memMinute, dailyAyahs: dailyAyahs
            )
        }
    }
}
