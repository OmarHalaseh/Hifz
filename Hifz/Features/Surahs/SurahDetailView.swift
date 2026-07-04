import SwiftUI
import SwiftData

struct SurahDetailView: View {
    let unit: TrackUnit

    @Environment(\.modelContext) private var context
    @Query private var allProgress: [MemorizationProgress]
    @Query private var settingsList: [AppSettings]

    @State private var status: MemorizationStatus = .notStarted
    @State private var strength: Double = 0.5
    @State private var reviewing = false

    private var settings: AppSettings { settingsList.first ?? AppSettings.current(in: context) }
    private var existing: MemorizationProgress? { allProgress.first { $0.unitKey == unit.key } }

    var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    if let arabic = unit.arabic {
                        Text(arabic)
                            .font(.system(size: 44, weight: .bold))
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
                Picker("Status", selection: $status) {
                    ForEach(MemorizationStatus.allCases) { s in
                        Text(s.label).tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: status) { _, newValue in applyStatus(newValue) }
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
            if let p = existing { status = p.status; strength = p.strength }
        }
        .sheet(isPresented: $reviewing) {
            if let p = existing {
                NavigationStack { SingleReviewView(progress: p) }
                    .presentationDetents([.medium])
            }
        }
    }

    private func applyStatus(_ newValue: MemorizationStatus) {
        let progress = ProgressManager.progress(for: unit, existing: allProgress, in: context)
        ProgressManager.setStatus(newValue, for: progress)
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
