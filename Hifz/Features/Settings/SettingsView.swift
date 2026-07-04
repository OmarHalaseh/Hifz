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
        return "At \(settings.dailyNewAyahs) new ayahs a day you'd finish the whole Quran in about \(GoalSetupView.humanDuration(days: days))."
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
                Stepper("\(settings.dailyNewAyahs) new ayahs per day", value: $settings.dailyNewAyahs, in: 1...100)
                    .onChange(of: settings.dailyNewAyahs) { _, _ in save(); rescheduleNotifications() }
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

            Section {
                Button(role: .destructive) {
                    showResetConfirm = true
                } label: {
                    Label("Reset all progress", systemImage: "trash")
                }
            } footer: {
                Text("Hifz \(appVersion) · All data is stored privately on your device.")
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

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
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
