import SwiftUI

/// The ḥifẓ plan at a glance: which surah is learned when (Sabaq), and what comes
/// up for revision on each of the next days (Sabqi + Manzil). A projection from
/// today's state — it re-forms as you go, so falling behind or racing ahead never
/// leaves a stale plan to "catch up" on.
struct HifzPlanView: View {
    let ayahs: [HifzAyah]
    let manuallyMemorizedKeys: Set<String>
    let lessonLines: Int
    let sabaqDoneToday: Bool
    let fromEnd: Bool

    enum Tab: String, CaseIterable, Identifiable {
        case learn = "Learn", revise = "Revise"
        var id: String { rawValue }
    }

    @State private var tab: Tab = .learn
    @State private var lessons: [HifzPlan.SurahLesson] = []
    @State private var revision: [HifzPlan.RevisionDay] = []
    @State private var showAllLessons = false

    private static let forecastDays = 14
    private static let lessonPreviewCount = 25

    var body: some View {
        List {
            Section {
                Picker("Plan", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            switch tab {
            case .learn: learnSections
            case .revise: reviseSections
            }
        }
        .navigationTitle("Plan")
        .navigationBarTitleDisplayMode(.inline)
        .task { build() }
    }

    // MARK: - Learn

    @ViewBuilder private var learnSections: some View {
        if lessons.isEmpty {
            Section {
                Text("Nothing left to learn — the whole Qur'an is memorized. Alḥamdulillāh.")
                    .foregroundStyle(.secondary)
            }
        } else {
            Section {
                if let last = lessons.last {
                    LabeledContent("Daily lesson", value: "\(lessonLines) line\(lessonLines == 1 ? "" : "s")")
                    LabeledContent("Surahs left", value: "\(lessons.count)")
                    LabeledContent("Finished by", value: last.end.formatted(date: .abbreviated, time: .omitted))
                }
            } footer: {
                Text("One new lesson a day at your lesson size. Learn on more days and everything moves earlier; skip days and it moves back.")
            }

            Section("Order") {
                let shown = showAllLessons ? lessons : Array(lessons.prefix(Self.lessonPreviewCount))
                ForEach(shown) { lesson in
                    lessonRow(lesson)
                }
                if !showAllLessons && lessons.count > Self.lessonPreviewCount {
                    Button("Show all \(lessons.count) surahs") { showAllLessons = true }
                }
            }
        }
    }

    private func lessonRow(_ lesson: HifzPlan.SurahLesson) -> some View {
        let meta = QuranData.surah(lesson.surah)
        let partial = lesson.firstAyah > 1 || lesson.lastAyah < (meta?.ayahCount ?? lesson.lastAyah)
        return HStack(spacing: 12) {
            Text("\(lesson.surah)")
                .font(.subheadline.monospacedDigit().weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                Text(meta?.transliteration ?? "Surah \(lesson.surah)").font(.body.weight(.medium))
                Text(dateRange(lesson) + (partial ? " · from ayah \(lesson.firstAyah)" : ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(lesson.days == 1 ? "1 day" : "\(lesson.days) days")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tint)
        }
    }

    private func dateRange(_ lesson: HifzPlan.SurahLesson) -> String {
        let s = dayLabel(lesson.start)
        return lesson.startDay == lesson.endDay ? s : "\(s) – \(dayLabel(lesson.end))"
    }

    // MARK: - Revise

    @ViewBuilder private var reviseSections: some View {
        let recent = sabqiSurahs
        if !recent.isEmpty {
            Section {
                ForEach(recent, id: \.self) { surah in
                    Label(QuranData.surah(surah)?.transliteration ?? "Surah \(surah)",
                          systemImage: HifzPhase.sabqi.systemImage)
                }
            } header: {
                Text("Sabqi · every day this week")
            } footer: {
                Text("Learned in the last 7 days. Recited daily, then they join the Manzil cycle below.")
            }
        }

        if revision.allSatisfy(\.blocks.isEmpty) {
            Section {
                Text("No long-term revision yet. Surahs join the Manzil cycle a week after you learn them.")
                    .foregroundStyle(.secondary)
            }
        } else {
            ForEach(revision) { day in
                Section {
                    if day.blocks.isEmpty {
                        Text("Nothing due").foregroundStyle(.secondary)
                    } else {
                        ForEach(day.blocks) { block in blockRow(block) }
                    }
                } header: {
                    HStack {
                        Text(dayLabel(day.date))
                        Spacer()
                        if !day.blocks.isEmpty {
                            Text("≈ \(Int(day.lines.rounded())) lines")
                        }
                    }
                }
            }
            Section {} footer: {
                Text("Short surahs are always revised whole; long ones are split into page-sized parts. Every part comes back at least once every \(HifzPageScheduler.manzilCapDays) days.")
            }
        }
    }

    private func blockRow(_ block: HifzPageScheduler.RevisionBlock) -> some View {
        let name = QuranData.surah(block.surah)?.transliteration ?? "Surah \(block.surah)"
        let pages = block.firstPage == block.lastPage
            ? "p. \(block.firstPage)" : "p. \(block.firstPage)–\(block.lastPage)"
        return VStack(alignment: .leading, spacing: 2) {
            Text(block.isWholeSurah ? name : "\(name) · part \(block.part) of \(block.partCount)")
                .font(.body.weight(.medium))
            Text("Ayah \(block.firstAyah)–\(block.lastAyah) · \(pages)")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// Surahs with ayahs still in their Sabqi week, in recitation order.
    private var sabqiSurahs: [Int] {
        let surahs = Set(HifzProgram.sabqiQueue(ayahs, fromEnd: fromEnd).map(\.surah))
            .union(recentlyMemorizedSurahs)
        return surahs.sorted { fromEnd ? $0 > $1 : $0 < $1 }
    }

    /// Includes surahs already recited today (no longer *due*, but still Sabqi).
    private var recentlyMemorizedSurahs: Set<Int> {
        let cal = Calendar.current
        guard let cutoff = cal.date(byAdding: .day, value: -HifzPageScheduler.sabqiDays,
                                    to: cal.startOfDay(for: .now)) else { return [] }
        return Set(ayahs.filter { ($0.memorizedAt ?? .distantPast) >= cutoff }.map(\.surah))
    }

    // MARK: - Building

    private func build() {
        var taken = Set(ayahs.filter(\.isMemorized).map(\.key))
        taken.formUnion(manuallyMemorizedKeys)
        let unlearned = HifzProgram.unlearnedAtoms(
            orderedAtoms: HifzText.orderedAtomTuples,
            memorizedOrInProgressKeys: taken, fromEnd: fromEnd
        ).map { (surah: $0.surah, ayah: $0.ayah) }

        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let start = sabaqDoneToday ? (cal.date(byAdding: .day, value: 1, to: today) ?? today) : today
        lessons = HifzPlan.sabaqSchedule(unlearned: unlearned, lines: lessonLines, start: start)

        revision = HifzPlan.revisionForecast(
            ayahs: ayahs.filter(\.isMemorized).map(HifzPageScheduler.AyahSnapshot.init),
            days: Self.forecastDays, fromEnd: fromEnd
        )
    }

    private func dayLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInTomorrow(date) { return "Tomorrow" }
        let sameYear = cal.component(.year, from: date) == cal.component(.year, from: .now)
        return date.formatted(sameYear
            ? .dateTime.weekday(.abbreviated).day().month(.abbreviated)
            : .dateTime.day().month(.abbreviated).year())
    }
}
