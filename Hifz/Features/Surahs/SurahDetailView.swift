import SwiftUI
import SwiftData

struct SurahDetailView: View {
    let unit: TrackUnit

    @Environment(\.modelContext) private var context
    @Query private var allProgress: [MemorizationProgress]
    @Query private var hifzAyahs: [HifzAyah]
    @Query private var settingsList: [AppSettings]

    @State private var status: MemorizationStatus = .notStarted
    @State private var strength: Double = 0.5
    @State private var reviewing = false
    /// The status the user picked when that means un-marking a memorized unit —
    /// held until they confirm, since it drops the unit's revision history.
    @State private var pendingDowngrade: MemorizationStatus?

    private var settings: AppSettings { settingsList.first ?? AppSettings.current(in: context) }
    private var existing: MemorizationProgress? { allProgress.first { $0.unitKey == unit.key } }

    /// What the rest of the app shows for this unit: the manual mark unioned with
    /// the ḥifẓ program's ayah coverage.
    private var effectiveStatus: MemorizationStatus {
        MemorizationCoverage.status(
            for: unit,
            memorizedKeys: MemorizationCoverage.memorizedKeys(from: hifzAyahs),
            stored: existing?.status
        )
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    if let arabic = unit.arabic {
                        Text(arabic)
                            .font(.quran(size: 44))
                            .environment(\.layoutDirection, .rightToLeft)
                    }
                    Text(unit.title).font(.title3.weight(.semibold))
                    Text(unit.subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }

            Section("Status") {
                Picker("Status", selection: Binding(get: { status }, set: pick)) {
                    ForEach(MemorizationStatus.allCases) { s in
                        Text(s.label).tag(s)
                    }
                }
                .pickerStyle(.segmented)
            }

            if status == .memorized, let p = existing {
                Section("Revision") {
                    LabeledContent("Next review", value: dueText(p))
                    LabeledContent("Interval", value: p.intervalDays == 0 ? "New" : "\(p.intervalDays) day\(p.intervalDays == 1 ? "" : "s")")
                    LabeledContent("Reviews", value: "\(p.repetitions)")
                    if let last = p.lastReviewedAt {
                        LabeledContent("Last reviewed", value: last.formatted(.relative(presentation: .named)))
                    }
                    Button {
                        reviewing = true
                    } label: {
                        Label("Review now", systemImage: "arrow.triangle.2.circlepath")
                    }
                }

                Section("Strength") {
                    VStack(alignment: .leading) {
                        Slider(value: $strength, in: 0...1) { editing in
                            if !editing { applyStrength() }
                        }
                        Text(strengthLabel).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(unit.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if unit.surahNumber > 0 {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SurahReaderView(
                            surahNumber: unit.surahNumber,
                            scrollTo: unit.granularity == .ayahRange ? unit.ayahFrom : nil
                        )
                    } label: {
                        Label("Read", systemImage: "book")
                    }
                }
            }
        }
        .onAppear {
            status = effectiveStatus
            if let p = existing { strength = p.strength }
        }
        .confirmationDialog(
            "Mark \(unit.title) as \(pendingDowngrade?.label.lowercased() ?? "")?",
            isPresented: Binding(get: { pendingDowngrade != nil },
                                 set: { if !$0 { pendingDowngrade = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove from memorized", role: .destructive) {
                if let target = pendingDowngrade { applyStatus(target) }
                pendingDowngrade = nil
            }
        } message: {
            Text("It leaves your revision (Sabqi/Manzil) and comes back as a new lesson. Its revision history is removed.")
        }
        .sheet(isPresented: $reviewing) {
            if let p = existing {
                NavigationStack { SingleReviewView(progress: p) }
                    .presentationDetents([.medium])
            }
        }
    }

    /// The picker's setter: un-marking something memorized waits for confirmation.
    private func pick(_ newValue: MemorizationStatus) {
        guard newValue != status else { return }
        if removesProgramAyahs(newValue) {
            pendingDowngrade = newValue
        } else {
            applyStatus(newValue)
        }
    }

    /// Whether moving to `newValue` means taking ayahs out of the ḥifẓ: anything
    /// below "memorized" for a memorized unit, or "not started" for one the
    /// program has partly covered.
    private func removesProgramAyahs(_ newValue: MemorizationStatus) -> Bool {
        switch newValue {
        case .memorized: return false
        case .learning: return effectiveStatus == .memorized
        case .notStarted:
            let keys = Set(MemorizationCoverage.ayahKeys(in: unit))
            return effectiveStatus == .memorized || hifzAyahs.contains { keys.contains($0.key) }
        }
    }

    private func applyStatus(_ newValue: MemorizationStatus) {
        if newValue == .memorized {
            let progress = ProgressManager.progress(for: unit, existing: allProgress, in: context)
            ProgressManager.setStatus(newValue, for: progress)
            // Seed per-ayah rows so a memorized unit enters the Manzil revision rotation.
            HifzProgramManager.seedMemorized(units: [unit], existing: hifzAyahs, in: context)
        } else if removesProgramAyahs(newValue) {
            HifzProgramManager.unmark(units: [unit], status: newValue, existing: hifzAyahs,
                                      progress: allProgress, in: context)
        } else {
            let progress = ProgressManager.progress(for: unit, existing: allProgress, in: context)
            ProgressManager.setStatus(newValue, for: progress)
        }
        status = newValue
        try? context.save()
    }

    private func applyStrength() {
        let progress = ProgressManager.progress(for: unit, existing: allProgress, in: context)
        progress.strength = strength
        try? context.save()
    }

    private func dueText(_ p: MemorizationProgress) -> String {
        guard let due = p.dueDate else { return "—" }
        if due <= Calendar.current.startOfDay(for: .now) { return "Due now" }
        return due.formatted(.relative(presentation: .named))
    }

    private var strengthLabel: String {
        switch strength {
        case ..<0.34: return "Weak — revise often"
        case ..<0.67: return "Medium"
        default: return "Strong"
        }
    }
}

/// A minimal review sheet for reviewing a single unit outside the queue.
struct SingleReviewView: View {
    let progress: MemorizationProgress
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Text("How well did you recall it?")
                .font(.headline)
                .padding(.top)
            RatingButtons { rating in
                ProgressManager.review(progress, rating: rating, in: context)
                try? context.save()
                dismiss()
            }
            Spacer()
        }
        .padding()
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
    }
}
