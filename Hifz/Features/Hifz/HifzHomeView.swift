import SwiftUI
import SwiftData

/// The daily ḥifẓ hub: assembles today's Sabqi / Sabaq / Manzil / weak-link
/// queues from the pure `HifzProgram` engine and launches a guided
/// `HifzSessionView` for each. This is the entry point for the ayah-atomic
/// Sabaq/Sabqi/Manzil program.
struct HifzHomeView: View {
    @Environment(\.modelContext) private var context

    @Query private var ayahs: [HifzAyah]
    @Query private var reviewLogs: [ReviewLog]
    @Query private var mistakeLogs: [MistakeLog]
    @Query private var stateList: [HifzProgramState]
    @Query private var settingsList: [AppSettings]

    @State private var active: ActiveSession?

    /// Memorize surahs from the end of the mushaf first (An-Nās → Al-Fātiḥa),
    /// the common back-to-front path. Shares its default with the surah list.
    @AppStorage("sabaqFromEnd") private var sabaqFromEnd = true

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
        let lines = HifzProgram.portionLines(
            baseLines: settings.sabaqUnit.baseLines, recentAccuracy: recentAccuracy
        )
        return HifzProgram.ayahCount(forLines: lines)
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
            if sabaqUnlocked {
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
            state: state, existing: ayahs, settings: settings,
            recentAccuracy: recentAccuracy, fromEnd: sabaqFromEnd, in: context
        )
        try? context.save()
        guard !rows.isEmpty else { return }
        active = ActiveSession(kind: .sabaq, ayahs: rows)
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

/// A pending session: which phase and the ayahs to drill.
private struct ActiveSession: Identifiable, Hashable {
    let id = UUID()
    let kind: HifzSessionView.Kind
    let ayahs: [HifzAyah]

    static func == (lhs: ActiveSession, rhs: ActiveSession) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
