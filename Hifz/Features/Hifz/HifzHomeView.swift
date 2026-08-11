import SwiftUI
import SwiftData

/// The daily ḥifẓ hub: assembles today's Sabqi / Sabaq / Manzil / weak-link
/// queues from the pure `HifzProgram` engine and launches a guided
/// `HifzSessionView` for each. This is the entry point for the ayah-atomic
/// Sabaq/Sabqi/Manzil program.
struct HifzHomeView: View {
    @Environment(\.modelContext) private var context

    @Query private var ayahs: [HifzAyah]
    @Query private var progress: [MemorizationProgress]
    @Query private var reviewLogs: [ReviewLog]
    @Query private var mistakeLogs: [MistakeLog]
    @Query private var stateList: [HifzProgramState]
    @Query private var settingsList: [AppSettings]

    @State private var active: ActiveSession?
    @State private var showDailyComplete = false
    @State private var previewCount = 0

    /// Memorize surahs from the end of the mushaf first (An-Nās → Al-Fātiḥa),
    /// the common back-to-front path. Shares its default with the surah list.
    @AppStorage("sabaqFromEnd") private var sabaqFromEnd = true

    /// Start-of-day (as a `timeIntervalSince1970`) the "good for today" popup
    /// was last shown, so it celebrates at most once per day.
    @AppStorage("dailyDoseCelebratedOn") private var celebratedOn: Double = 0

    private var state: HifzProgramState { stateList.first ?? HifzProgramState.current(in: context) }
    private var settings: AppSettings { settingsList.first ?? AppSettings.current(in: context) }

    // MARK: - Derived queues (pure engine)

    private var memorized: [HifzAyah] { ayahs.filter(\.isMemorized) }
    private var sabqi: [HifzAyah] { HifzProgram.sabqiQueue(ayahs, fromEnd: sabaqFromEnd) }
    /// Long-term revision is now scheduled per page with a hard 30-day cap
    /// (`HifzPageScheduler`), budgeted in lines — not by a rotation cursor.
    private var manzil: [HifzAyah] { HifzPageScheduler.manzilDueAyahs(from: ayahs, fromEnd: sabaqFromEnd) }
    private var weakLinks: [HifzAyah] { HifzProgram.weakLinks(ayahs) }

    private var recentAccuracy: Double {
        HifzProgramManager.recentAccuracy(reviews: reviewLogs, mistakes: mistakeLogs)
    }

    private var sabaqUnlocked: Bool {
        HifzProgram.isSabaqUnlocked(sabqiCount: sabqi.count, sabqiClearedOn: state.sabqiClearedOn)
    }

    /// Ayahs in today's Sabaq portion (already assigned today, or a sized preview).
    private var sabaqPortionCount: Int {
        if let assigned = state.sabaqAssignedOn,
           Calendar.current.isDate(assigned, inSameDayAs: .now), !state.sabaqKeys.isEmpty {
            return state.sabaqKeys.count
        }
        return previewCount
    }

    /// Cheap signature of everything the preview depends on, so the portion is only
    /// re-measured when it can actually have changed — sizing it walks all 6236
    /// atoms and is far too costly to redo on every render.
    private var previewSignature: String {
        "\(ayahs.count)|\(progress.count)|\(settings.sabaqUnit.rawValue)|\(sabaqFromEnd)"
            + "|\(Int(recentAccuracy * 100))"
    }

    private func refreshPreviewCount() {
        previewCount = HifzProgramManager.sabaqPortionAtoms(
            existing: ayahs,
            manuallyMemorizedKeys: MemorizationCoverage.manuallyMemorizedAyahKeys(from: progress),
            settings: settings, recentAccuracy: recentAccuracy, fromEnd: sabaqFromEnd
        ).count
    }

    /// Today's Sabaq portion has been assigned and every ayah in it confirmed.
    private var sabaqDoneToday: Bool {
        guard let assigned = state.sabaqAssignedOn,
              Calendar.current.isDate(assigned, inSameDayAs: .now),
              !state.sabaqKeys.isEmpty else { return false }
        return Set(state.sabaqKeys).isSubset(of: Set(state.sabaqConfirmedKeys))
    }

    /// Everything due today is cleared: recent work recited, a new lesson learned,
    /// and the long-term cycle and weak links are empty. Requires that the user
    /// has actually memorized something (otherwise there's no "dose" yet).
    private var dailyDoseComplete: Bool {
        !memorized.isEmpty
            && sabqi.isEmpty
            && manzil.isEmpty
            && weakLinks.isEmpty
            && sabaqDoneToday
    }

    var body: some View {
        NavigationStack {
            List {
                summarySection
                sabqiSection
                sabaqSection
                manzilSection
                weakLinkSection
            }
            .navigationTitle("Ḥifẓ")
            .navigationDestination(item: $active) { session in
                HifzSessionView(
                    kind: session.kind,
                    ayahs: session.ayahs,
                    state: state,
                    onFinish: { finish(session.kind) }
                )
            }
        }
        .onChange(of: dailyDoseComplete) { _, complete in
            if complete { celebrateIfNeeded() }
        }
        .onAppear { celebrateIfNeeded() }
        .task(id: previewSignature) { refreshPreviewCount() }
        .sheet(isPresented: $showDailyComplete) {
            DailyCompleteView(
                memorizedCount: memorized.count,
                pageCount: Set(memorized.map(\.page)).count
            )
            .presentationDetents([.medium])
        }
    }

    // MARK: - Sections

    private var summarySection: some View {
        Section {
            HStack(spacing: 24) {
                stat(value: "\(memorized.count)", label: "Ayahs")
                stat(value: "\(Set(memorized.map(\.page)).count)", label: "Pages")
                stat(value: "\(Int(recentAccuracy * 100))%", label: "Accuracy")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder private var sabqiSection: some View {
        if !sabqi.isEmpty {
            Section {
                PhaseCard(phase: .sabqi, count: sabqi.count,
                          note: "Recite before starting a new lesson.") {
                    active = ActiveSession(kind: .sabqi, ayahs: sabqi)
                }
            }
        }
    }

    private var sabaqSection: some View {
        Section {
            if sabaqDoneToday {
                sabaqDone
            } else if sabaqUnlocked {
                PhaseCard(phase: .sabaq, count: sabaqPortionCount,
                          note: "Learn a new portion. Confirm only on a flawless recall.") {
                    startSabaq()
                }
            } else {
                lockedSabaq
            }
        } footer: {
            if memorized.isEmpty {
                Text("Each day, recite your Sabqi (recent work) first, then learn a new Sabaq portion — mark an ayah memorized only after a flawless recitation from memory. Manzil keeps older pages fresh on a rotation. Small and daily beats large and rare.")
            }
        }
    }

    @ViewBuilder private var manzilSection: some View {
        if !manzil.isEmpty {
            Section {
                PhaseCard(phase: .manzil, count: manzil.count,
                          note: "Today's slice of the long-term cycle.") {
                    active = ActiveSession(kind: .manzil, ayahs: manzil)
                }
            }
        }
    }

    @ViewBuilder private var weakLinkSection: some View {
        if !weakLinks.isEmpty {
            Section {
                Button { active = ActiveSession(kind: .weakLinks, ayahs: weakLinks) } label: {
                    CardLabel(systemImage: "exclamationmark.triangle.fill",
                              title: "Weak links", subtitle: "Ayahs missed repeatedly — extra reps.",
                              count: weakLinks.count, tint: .orange)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var sabaqDone: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2).foregroundStyle(.green)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("Today's lesson done").font(.body.weight(.medium))
                Text("New Sabaq confirmed. It returns for Sabqi on its next due day.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var lockedSabaq: some View {
        HStack(spacing: 14) {
            Image(systemName: "lock.fill")
                .font(.title2).foregroundStyle(.secondary)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("New lesson locked").font(.body.weight(.medium))
                Text("Clear today's Sabqi first to unlock a new Sabaq.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func stat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.weight(.semibold))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private func startSabaq() {
        let rows = HifzProgramManager.ensureTodaysSabaq(
            state: state, existing: ayahs,
            manuallyMemorizedKeys: MemorizationCoverage.manuallyMemorizedAyahKeys(from: progress),
            settings: settings,
            recentAccuracy: recentAccuracy, fromEnd: sabaqFromEnd, in: context
        )
        try? context.save()
        guard !rows.isEmpty else { return }
        active = ActiveSession(kind: .sabaq, ayahs: rows)
    }

    /// Shows the "good for today" popup the first time the daily dose is
    /// completed each day, then remembers the day so it won't repeat.
    private func celebrateIfNeeded() {
        guard dailyDoseComplete else { return }
        let today = Calendar.current.startOfDay(for: .now).timeIntervalSince1970
        guard celebratedOn != today else { return }
        celebratedOn = today
        showDailyComplete = true
    }

    private func finish(_ kind: HifzSessionView.Kind) {
        switch kind {
        case .sabqi:
            HifzProgramManager.clearSabqi(state: state)
        case .manzil:
            // Reviewing each ayah already advanced its SR state (and thus the page's
            // 30-day-capped due date), so the page leaves today's queue on its own —
            // no rotation cursor to advance.
            break
        case .sabaq, .weakLinks:
            break
        }
        try? context.save()
    }
}

/// A tappable phase card built from `HifzPhase`'s own label/subtitle/icon.
private struct PhaseCard: View {
    let phase: HifzPhase
    let count: Int
    let note: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                CardLabel(systemImage: phase.systemImage, title: phase.label,
                          subtitle: phase.subtitle, count: count, tint: .accentColor)
                Text(note).font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }
}

/// The icon + title + count row shared by every card.
private struct CardLabel: View {
    let systemImage: String
    let title: String
    let subtitle: String
    let count: Int
    let tint: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2).foregroundStyle(tint)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(count)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(tint)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
    }
}

/// Celebratory "you're good for today" popup shown once the whole daily
/// dose — Sabqi, Sabaq, Manzil and weak links — is cleared.
private struct DailyCompleteView: View {
    let memorizedCount: Int
    let pageCount: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: memorizedCount)
            VStack(spacing: 6) {
                Text("You're good for today")
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                Text("Sabqi, Sabaq and Manzil are all done. Come back tomorrow to keep the streak going.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 28) {
                stat("\(memorizedCount)", "Ayahs")
                stat("\(pageCount)", "Pages")
            }
            .padding(.top, 4)
            Spacer()
            Button {
                dismiss()
            } label: {
                Text("Alḥamdulillāh")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(24)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.weight(.semibold))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

/// A pending session: which phase and the ayahs to drill.
private struct ActiveSession: Identifiable, Hashable {
    let id = UUID()
    let kind: HifzSessionView.Kind
    let ayahs: [HifzAyah]

    static func == (lhs: ActiveSession, rhs: ActiveSession) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
