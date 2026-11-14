import SwiftUI
import SwiftData

/// One guided ḥifẓ session.
///
/// **Sabaq (new lesson)** runs a progressive drill: repeat the first ayah, then
/// the second on its own, then both together, then the third, then connect it to
/// the ayahs just before it — building up until the whole lesson is recited once
/// from the start and confirmed memorized. The position is remembered, so a
/// lesson left half-way resumes at the same step.
///
/// **Sabqi / Manzil / weak-links (revision)** present the assigned ayahs as
/// **passages** — a connected part of a surah, about half a page — with the text
/// hidden by default, so you recite the stretch from memory before revealing to
/// check. A mistake is then pinned to the ayah(s) it happened in, so the rest of
/// the passage still counts as recited correctly, and the passage comes back
/// once more at the end of the session for a second pass.
struct HifzSessionView: View {
    enum Kind { case sabaq, sabqi, manzil, weakLinks }

    let kind: Kind
    let ayahs: [HifzAyah]
    let state: HifzProgramState
    var onFinish: () -> Void = {}

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @StateObject private var audio = QariAudio.shared

    /// Revision only: `ayahs` grouped into connected passages of a surah, followed
    /// by any passages queued for a second pass after a mistake.
    @State private var passages: [[HifzAyah]]
    /// Passages before this index are the first round; the rest are second passes.
    private let firstRoundCount: Int
    /// Sabaq only: the drill, built once.
    private let drillSteps: [DrillStep]

    @State private var index = 0       // revision: current passage
    @State private var pickingMistakes = false   // choosing which ayahs went wrong
    @State private var mistaken: Set<String> = []
    @State private var wasHiddenAtMistake = false
    @State private var stepIndex = 0   // sabaq: current drill step
    @State private var reps = 0
    @State private var hidden: Bool     // "recite from memory" — blur the text

    /// Recommended number of times to repeat each new ayah while drilling Sabaq.
    private let repTarget = 7...10
    /// Repetitions a connecting recap needs before you may move on.
    private let recapMinReps = 3

    /// Repetitions the current step needs before "Next" / "finish" unlocks — so
    /// nothing is confirmed memorized without actually drilling it.
    private var requiredReps: Int {
        (currentStep?.isRecap ?? false) ? recapMinReps : repTarget.lowerBound
    }
    private var stepDrilled: Bool { reps >= requiredReps }

    init(kind: Kind, ayahs: [HifzAyah], state: HifzProgramState, onFinish: @escaping () -> Void = {}) {
        self.kind = kind
        self.ayahs = ayahs
        self.state = state
        self.onFinish = onFinish
        let grouped = kind == .sabaq
            ? [] : HifzProgram.passages(ayahs, maxLines: HifzProgram.storedPassageLines())
        _passages = State(initialValue: grouped)
        self.firstRoundCount = grouped.count
        let steps = kind == .sabaq
            ? HifzProgram.drillSteps(costs: ayahs.map {
                max(0, MushafLayout.lineCost(surah: $0.surah, ayah: $0.ayah)) })
                .map { DrillStep(range: $0, lessonCount: ayahs.count) }
            : []
        self.drillSteps = steps
        // Revision defaults to hidden so you recite from memory first.
        _hidden = State(initialValue: kind != .sabaq)
        // Resume a Sabaq lesson that was left half-way.
        if kind == .sabaq, let saved = SabaqDrillProgress.load(for: ayahs), saved.step < steps.count {
            _stepIndex = State(initialValue: saved.step)
            _reps = State(initialValue: saved.reps)
        }
    }

    /// The blur state a fresh ayah/step returns to.
    private var defaultHidden: Bool { kind != .sabaq }

    // MARK: - Sabaq drill

    /// One step of the drill: a single new ayah, or a recap connecting it to the
    /// ayahs before it.
    private struct DrillStep {
        let range: ClosedRange<Int>   // indices into `ayahs`
        let lessonCount: Int
        var isRecap: Bool { range.count > 1 }
        /// The recap that covers the entire lesson.
        var isWholeLesson: Bool { isRecap && range.count == lessonCount }
    }

    private var currentStep: DrillStep? {
        drillSteps.indices.contains(stepIndex) ? drillSteps[stepIndex] : nil
    }

    private var isLastStep: Bool { stepIndex >= drillSteps.count - 1 }

    // MARK: - Displayed ayahs (unifies both modes)

    private var currentPassage: [HifzAyah] { passages.indices.contains(index) ? passages[index] : [] }

    /// The ayah(s) currently on screen: a drill step's range for Sabaq, or the
    /// current revision passage otherwise.
    private var displayed: [HifzAyah] {
        if kind == .sabaq {
            guard let step = currentStep else { return [] }
            return step.range.map { ayahs[$0] }
        }
        return currentPassage
    }

    /// The current passage is back for a second pass after a mistake.
    private var isSecondPass: Bool { index >= firstRoundCount }

    /// Weak links only: the ayah *before* the passage, shown greyed as a run-up —
    /// a weak ayah is usually lost at the join from the previous one.
    private var leadIn: (surah: Int, ayah: Int)? {
        guard kind == .weakLinks, let first = currentPassage.first, first.ayah > 1 else { return nil }
        return (first.surah, first.ayah - 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            progressBar
            ScrollView {
                VStack(spacing: 20) {
                    if let first = displayed.first {
                        headerLabel(displayed, page: first.page)
                        ayahCard(displayed)
                        audioAndReveal(displayed)
                    }
                }
                .padding()
            }
            controls
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .onDisappear { audio.stop() }
    }

    private var title: String {
        switch kind {
        case .sabaq: return "Sabaq · New lesson"
        case .sabqi: return "Sabqi · Recent revision"
        case .manzil: return "Manzil · Revision"
        case .weakLinks: return "Weak links"
        }
    }

    private var progressBar: some View {
        let value: Double
        let total: Double
        let label: String
        if kind == .sabaq {
            value = Double(stepIndex)
            total = Double(max(1, drillSteps.count))
            label = "Step \(min(stepIndex + 1, drillSteps.count)) of \(drillSteps.count)"
        } else {
            value = Double(index)
            total = Double(max(1, passages.count))
            label = isSecondPass
                ? "Second pass · \(index - firstRoundCount + 1) of \(passages.count - firstRoundCount)"
                : "Passage \(min(index + 1, firstRoundCount)) of \(firstRoundCount)"
        }
        return VStack(spacing: 4) {
            ProgressView(value: value, total: total)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal).padding(.top, 8)
    }

    private func headerLabel(_ group: [HifzAyah], page: Int) -> some View {
        let first = group.first!
        let last = group.last!
        let surahName = QuranData.surah(first.surah)?.transliteration ?? "Surah \(first.surah)"
        let ayahLabel = group.count == 1
            ? "Ayah \(first.ayah)"
            : "Ayah \(first.ayah)–\(last.ayah)"
        return HStack {
            Label("\(surahName) · \(ayahLabel)", systemImage: "text.book.closed")
                .font(.subheadline.weight(.medium))
            Spacer()
            Text("Page \(page)").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func ayahCard(_ group: [HifzAyah]) -> some View {
        arabic(for: group)
            .font(.quran(size: 30))
            .lineSpacing(6)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .environment(\.layoutDirection, .rightToLeft)
            .padding(.vertical, 28).padding(.horizontal, 16)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemGroupedBackground)))
            .overlay {
                if hidden {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18).fill(.ultraThinMaterial)
                        VStack(spacing: 6) {
                            Image(systemName: "eye.slash").font(.title)
                            Text("Recite from memory").font(.subheadline.weight(.medium))
                        }.foregroundStyle(.secondary)
                    }
                }
            }
    }

    /// Tajweed-coloured Arabic for one or more ayahs (falls back to plain text).
    /// In a recap (multiple ayahs) each ayah ends with its number in an
    /// end-of-ayah marker so the connections are visible.
    private func arabic(for group: [HifzAyah]) -> Text {
        let showMarkers = group.count > 1 || leadIn != nil
        var start = Text("")
        if kind != .sabaq, let lead = leadIn,
           let text = QuranText.ayah(surah: lead.surah, ayah: lead.ayah)?.ar {
            start = Text("\(text) \(ayahEndMarker(lead.ayah)) ").foregroundColor(.secondary)
        }
        return group.reduce(start) { acc, a in
            let piece: Text
            if let runs = TajweedText.runs(surah: a.surah, ayah: a.ayah) {
                piece = runs.reduce(Text("")) { $0 + Text($1.text).foregroundColor($1.rule?.color ?? .primary) }
            } else {
                piece = Text(QuranText.ayah(surah: a.surah, ayah: a.ayah)?.ar ?? "")
            }
            let marker = showMarkers
                ? Text(" \(ayahEndMarker(a.ayah)) ").foregroundColor(.accentColor)
                : Text("  ")
            return acc + piece + marker
        }
    }

    private func audioAndReveal(_ group: [HifzAyah]) -> some View {
        HStack(spacing: 12) {
            Button {
                audio.play(sequence: group.map { ($0.surah, $0.ayah) })
            } label: {
                Label(audio.playingKey != nil ? "Playing…" : "Listen to qari",
                      systemImage: "play.circle.fill")
            }
            .buttonStyle(.bordered)

            Button {
                withAnimation(.snappy) { hidden.toggle() }
            } label: {
                Label(hidden ? "Show" : "Hide", systemImage: hidden ? "eye" : "eye.slash")
            }
            .buttonStyle(.bordered)
        }
        .font(.subheadline)
    }

    // MARK: - Phase controls

    @ViewBuilder private var controls: some View {
        VStack(spacing: 12) {
            if kind == .sabaq {
                sabaqControls
            } else {
                revisionControls
            }
        }
        .padding()
        .background(.bar)
    }

    private var sabaqControls: some View {
        VStack(spacing: 10) {
            HStack {
                Text(stepDrilled
                     ? "Repeated \(reps)× ✓"
                     : "Repeated \(reps)× — at least \(requiredReps) to continue")
                    .font(.subheadline)
                    .foregroundStyle(stepDrilled ? Color.green : .secondary)
                Spacer()
                Button {
                    reps += 1
                    SabaqDrillProgress.save(step: stepIndex, reps: reps, for: ayahs)
                } label: { Label("Repeat", systemImage: "repeat") }
                    .buttonStyle(.bordered)
                    .disabled(reps >= 15)
            }
            Text(stepHint)
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if isLastStep {
                Button { finishSabaq() } label: {
                    Label("Memorized — finish lesson", systemImage: "checkmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!stepDrilled)
            } else {
                Button { nextStep() } label: {
                    Label("Next", systemImage: "arrow.right").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!stepDrilled)
            }
        }
    }

    /// Guidance tailored to the current drill step.
    private var stepHint: String {
        guard let step = currentStep else { return "" }
        if step.isWholeLesson {
            return "Now the whole lesson from the start — recite it as one at least \(recapMinReps) times, the last from memory."
        }
        if step.isRecap {
            return "Now connect the new ayah to the ones before it — recite them as one at least \(recapMinReps) times, the last from memory."
        }
        if step.range.lowerBound == 0 {
            return "Repeat this ayah \(repTarget.lowerBound)–\(repTarget.upperBound) times until it flows. Hide it and recite from memory before continuing."
        }
        return "Learn this new ayah on its own — repeat it \(repTarget.lowerBound)–\(repTarget.upperBound) times, then hide and recite it."
    }

    @ViewBuilder private var revisionControls: some View {
        if pickingMistakes {
            mistakePicker
        } else {
            Text(revisionHint)
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 12) {
                Button(role: .destructive) { beginMistake() } label: {
                    Label("Mistake", systemImage: "xmark").frame(maxWidth: .infinity)
                }.buttonStyle(.bordered)
                Button { grade(mistakes: []) } label: {
                    Label("Correct", systemImage: "checkmark").frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent)
            }
        }
    }

    private var revisionHint: String {
        if isSecondPass {
            return "Second pass — this passage had a mistake. Recite it once more from memory."
        }
        if leadIn != nil {
            return "Start from the grey ayah and recite on through the passage from memory, then reveal to check."
        }
        return currentPassage.count > 1
            ? "Recite the whole passage from memory, then reveal to check."
            : "Recite from memory, then reveal to check."
    }

    /// After "Mistake" on a multi-ayah passage: pick the ayah(s) it happened in.
    private var mistakePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Which ayahs had a mistake?").font(.subheadline.weight(.medium))
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 8)], spacing: 8) {
                    ForEach(currentPassage, id: \.key) { a in
                        let on = mistaken.contains(a.key)
                        Button {
                            if on { mistaken.remove(a.key) } else { mistaken.insert(a.key) }
                        } label: {
                            Text("\(a.ayah)")
                                .font(.callout.monospacedDigit().weight(.medium))
                                .frame(maxWidth: .infinity, minHeight: 36)
                                .background(RoundedRectangle(cornerRadius: 8)
                                    .fill(on ? Color.red.opacity(0.85) : Color(.tertiarySystemFill)))
                                .foregroundStyle(on ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Ayah \(a.ayah)")
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
            .frame(maxHeight: 140)
            HStack(spacing: 12) {
                Button {
                    pickingMistakes = false
                    mistaken = []
                } label: { Text("Cancel").frame(maxWidth: .infinity) }
                .buttonStyle(.bordered)
                Button { grade(mistakes: mistaken) } label: {
                    Text(mistaken.isEmpty ? "Select ayahs" : "Confirm \(mistaken.count)")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(mistaken.isEmpty)
            }
        }
    }

    // MARK: - Actions

    /// Advance the Sabaq drill to the next step.
    private func nextStep() {
        audio.stop()
        reps = 0
        hidden = defaultHidden
        withAnimation { stepIndex += 1 }
        SabaqDrillProgress.save(step: stepIndex, reps: 0, for: ayahs)
    }

    /// The whole lesson is connected — confirm every ayah memorized.
    private func finishSabaq() {
        for a in ayahs { HifzProgramManager.confirmFlawless(a, state: state, in: context) }
        try? context.save()
        SabaqDrillProgress.clear()
        audio.stop()
        onFinish()
        dismiss()
    }

    /// "Mistake" tapped: a single ayah is graded at once; for a passage, reveal the
    /// text and ask which ayah(s) went wrong.
    private func beginMistake() {
        wasHiddenAtMistake = hidden
        guard currentPassage.count > 1 else {
            grade(mistakes: Set(currentPassage.map(\.key)))
            return
        }
        mistaken = []
        withAnimation(.snappy) {
            hidden = false
            pickingMistakes = true
        }
    }

    /// Grades the current passage — the ayahs in `mistakes` as missed, every other
    /// ayah as recited correctly — and moves on.
    private func grade(mistakes: Set<String>) {
        let rating: ReviewRating = kind == .weakLinks ? .hard : .good
        for a in currentPassage {
            if mistakes.contains(a.key) {
                HifzProgramManager.recordMistake(a, kind: wasHiddenAtMistake ? "stuck" : "slip", in: context)
            } else {
                HifzProgramManager.recordCorrect(a, rating: rating,
                                                 healsWeakLink: kind == .weakLinks, in: context)
            }
        }
        try? context.save()
        // A passage with a mistake returns once at the end for a second pass.
        if !mistakes.isEmpty, !isSecondPass { passages.append(currentPassage) }
        next()
    }

    /// Advance the revision session to the next passage.
    private func next() {
        audio.stop()
        reps = 0
        hidden = defaultHidden
        pickingMistakes = false
        mistaken = []
        if index + 1 < passages.count {
            withAnimation { index += 1 }
        } else {
            onFinish()
            try? context.save()
            dismiss()
        }
    }
}

/// Where a half-finished Sabaq drill stands, kept in `UserDefaults` (not the
/// store: it is throwaway UI position, tied to one lesson by its ayah keys).
private enum SabaqDrillProgress {
    private static let stepKey = "sabaqDrillStep"
    private static let repsKey = "sabaqDrillReps"

    private static func id(_ ayahs: [HifzAyah]) -> String { ayahs.map(\.key).joined(separator: ",") }

    static func load(for ayahs: [HifzAyah], defaults: UserDefaults = .standard) -> (step: Int, reps: Int)? {
        guard !ayahs.isEmpty,
              defaults.string(forKey: HifzProgram.sabaqDrillLessonKey) == id(ayahs) else { return nil }
        return (max(0, defaults.integer(forKey: stepKey)), max(0, defaults.integer(forKey: repsKey)))
    }

    static func save(step: Int, reps: Int, for ayahs: [HifzAyah], defaults: UserDefaults = .standard) {
        defaults.set(id(ayahs), forKey: HifzProgram.sabaqDrillLessonKey)
        defaults.set(step, forKey: stepKey)
        defaults.set(reps, forKey: repsKey)
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: HifzProgram.sabaqDrillLessonKey)
    }
}
