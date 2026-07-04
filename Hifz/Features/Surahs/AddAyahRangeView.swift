import SwiftUI
import SwiftData

/// Sheet for creating a new ayah-range unit within a surah.
struct AddAyahRangeView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var surahNumber = 1
    @State private var from = 1
    @State private var to = 7

    private var surah: Surah? { QuranData.surah(surahNumber) }
    private var maxAyah: Int { surah?.ayahCount ?? 1 }

    var body: some View {
        NavigationStack {
            Form {
                Section("Surah") {
                    Picker("Surah", selection: $surahNumber) {
                        ForEach(QuranData.surahs) { s in
                            Text("\(s.number). \(s.transliteration)").tag(s.number)
                        }
                    }
                    .onChange(of: surahNumber) { _, _ in
                        from = 1
                        to = min(maxAyah, 7)
                    }
                }
                Section("Ayahs") {
                    Stepper("From ayah \(from)", value: $from, in: 1...maxAyah)
                        .onChange(of: from) { _, newValue in if to < newValue { to = newValue } }
                    Stepper("To ayah \(to)", value: $to, in: from...maxAyah)
                    Text("\(surah?.transliteration ?? "") \(from)–\(to) · \(to - from + 1) ayah\(to - from == 0 ? "" : "s")")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add Ayah Range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Add") { add() } }
            }
        }
    }

    private func add() {
        let unit = QuranData.ayahUnit(surah: surahNumber, from: from, to: to)
        // Avoid duplicates.
        let descriptor = FetchDescriptor<MemorizationProgress>()
        let all = (try? context.fetch(descriptor)) ?? []
        let progress = ProgressManager.progress(for: unit, existing: all, in: context)
        if progress.status == .notStarted { progress.status = .learning }
        try? context.save()
        dismiss()
    }
}
