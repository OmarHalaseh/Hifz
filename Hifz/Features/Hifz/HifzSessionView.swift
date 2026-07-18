import SwiftUI
import SwiftData

/// One guided ḥifẓ session.
///
/// **Sabaq (new lesson)** runs a progressive, cumulative drill: repeat the first
/// ayah, then the second on its own, then both together, then the third, then all
/// three together — building up until the whole lesson (a full or half page) is
/// connected, then the lesson is confirmed memorized.
///
/// **Sabqi / Manzil / weak-links (revision)** present assigned ayahs one at a
/// time with the text hidden by default, so you recite from memory before
/// revealing to check.
struct HifzSessionView: View {
    enum Kind { case sabaq, sabqi, manzil, weakLinks }

    let kind: Kind
    let ayahs: [HifzAyah]
    let state: HifzProgramState
    var onFinish: () -> Void = {}

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @StateObject private var audio = QariAudio.shared

    @State private var index = 0       // revision: current ayah
    @State private var stepIndex = 0   // sabaq: current drill step
    @State private var reps = 0
    @State private var hidden: Bool     // "recite from memory" — blur the text

    /// Recommended number of times to repeat each new ayah while drilling Sabaq.
    private let repTarget = 7...10

    init(kind: Kind, ayahs: [HifzAyah], state: HifzProgramState, onFinish: @escaping () -> Void = {}) {
        self.kind = kind
        self.ayahs = ayahs
        self.state = state
        self.onFinish = onFinish
        // Revision defaults to hidden so you recite from memory first.
        _hidden = State(initialValue: kind != .sabaq)
    }

    /// The blur state a fresh ayah/step returns to.
    private var defaultHidden: Bool { kind != .sabaq }

    // MARK: - Sabaq drill

    /// One step of the cumulative drill: a single new ayah, or a recap spanning
    /// the lesson's start up to the newest ayah.
    private struct DrillStep {
        let range: ClosedRange<Int>   // indices into `ayahs`
        var isRecap: Bool { range.count > 1 }
    }

    /// Interleaves each new ayah with a cumulative recap: [0], [1], [0…1], [2], [0…2], …
    private var drillSteps: [DrillStep] {
        guard !ayahs.isEmpty else { return [] }
        var steps: [DrillStep] = []
        for i in ayahs.indices {
            steps.append(DrillStep(range: i...i))
            if i > 0 { steps.append(DrillStep(range: 0...i)) }
        }
        return steps
    }

    private var currentStep: DrillStep? {
        drillSteps.indices.contains(stepIndex) ? drillSteps[stepIndex] : nil
    }

    private var isLastStep: Bool { stepIndex >= drillSteps.count - 1 }

    // MARK: - Displayed ayahs (unifies both modes)

    private var current: HifzAyah? { ayahs.indices.contains(index) ? ayahs[index] : nil }

    /// The ayah(s) currently on screen: a drill step's range for Sabaq, or the
    /// single revision ayah otherwise.
    private var displayed: [HifzAyah] {
        if kind == .sabaq {
            guard let step = currentStep else { return [] }
            return step.range.map { ayahs[$0] }
        }
        return current.map { [$0] } ?? []
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
            total = Double(max(1, ayahs.count))
            label = "\(min(index + 1, ayahs.count)) of \(ayahs.count)"
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
            .font(.system(size: 30, weight: .regular))
            .lineSpacing(16)
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
        let showMarkers = group.count > 1
        return group.reduce(Text("")) { acc, a in
            let piece: Text
            if let runs = TajweedText.runs(surah: a.surah, ayah: a.ayah) {
                piece = runs.reduce(Text("")) { $0 + Text($1.text).foregroundColor($1.rule?.color ?? .primary) }
            } else {
                piece = Text(QuranText.ayah(surah: a.surah, ayah: a.ayah)?.ar ?? "")
            }
            let marker = showMarkers
                ? Text(" \u{06DD}\(arabicIndic(a.ayah)) ").foregroundColor(.accentColor)
                : Text("  ")
            return acc + piece + marker
        }
    }

    /// Western digits rendered as Arabic-Indic (١٢٣) for the ayah marker.
    private func arabicIndic(_ n: Int) -> String {
        let map: [Character: Character] = [
            "0": "٠", "1": "١", "2": "٢", "3": "٣", "4": "٤",
            "5": "٥", "6": "٦", "7": "٧", "8": "٨", "9": "٩",
        ]
        return String(String(n).map { map[$0] ?? $0 })
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
                Text(reps >= repTarget.lowerBound
                     ? "Repeated \(reps)× ✓"
                     : "Repeated \(reps)× — aim for \(repTarget.lowerBound)–\(repTarget.upperBound)")
                    .font(.subheadline)
                    .foregroundStyle(reps >= repTarget.lowerBound ? Color.green : .secondary)
                Spacer()
                Button {
                    reps += 1
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
            } else {
                Button { nextStep() } label: {
                    Label("Next", systemImage: "arrow.right").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    /// Guidance tailored to the current drill step.
    private var stepHint: String {
        guard let step = currentStep else { return "" }
        if step.isRecap {
            return "Now connect these ayahs together from the start. Hide the text and recite them as one before moving on."
        }
        if step.range.lowerBound == 0 {
            return "Repeat this ayah \(repTarget.lowerBound)–\(repTarget.upperBound) times until it flows. Hide it and recite from memory before continuing."
        }
        return "Learn this new ayah on its own — repeat it \(repTarget.lowerBound)–\(repTarget.upperBound) times, then hide and recite it."
    }

    private var revisionControls: some View {
        HStack(spacing: 12) {
            Button(role: .destructive) { mistake(); next() } label: {
                Label("Mistake", systemImage: "xmark").frame(maxWidth: .infinity)
            }.buttonStyle(.bordered)
            Button { correct(); next() } label: {
                Label("Correct", systemImage: "checkmark").frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Actions

    /// Advance the Sabaq drill to the next step.
    private func nextStep() {
        audio.stop()
        reps = 0
        hidden = defaultHidden
        withAnimation { stepIndex += 1 }
    }

    /// The whole lesson is connected — confirm every ayah memorized.
    private func finishSabaq() {
        for a in ayahs { HifzProgramManager.confirmFlawless(a, state: state) }
        try? context.save()
        audio.stop()
        onFinish()
        dismiss()
    }

    private func correct() {
        guard let c = current else { return }
        let rating: ReviewRating = kind == .weakLinks ? .hard : .good
        HifzProgramManager.recordCorrect(c, rating: rating, in: context)
        try? context.save()
    }

    private func mistake() {
        guard let c = current else { return }
        HifzProgramManager.recordMistake(c, kind: hidden ? "stuck" : "slip", in: context)
        try? context.save()
    }

    /// Advance the revision session to the next ayah.
    private func next() {
        audio.stop()
        reps = 0
        hidden = defaultHidden
        if index + 1 < ayahs.count {
            withAnimation { index += 1 }
        } else {
            onFinish()
            try? context.save()
            dismiss()
        }
    }
}
