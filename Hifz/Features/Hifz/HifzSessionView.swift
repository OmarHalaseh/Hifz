import SwiftUI
import SwiftData

/// One guided ḥifẓ session. Presents assigned ayahs one at a time on the mushaf
/// text, with qari audio, a repeat counter, a reveal/hide toggle for reciting
/// from memory, and the phase-appropriate confirm / mistake controls.
struct HifzSessionView: View {
    enum Kind { case sabaq, sabqi, manzil, weakLinks }

    let kind: Kind
    let ayahs: [HifzAyah]
    let state: HifzProgramState
    var onFinish: () -> Void = {}

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @StateObject private var audio = QariAudio.shared

    @State private var index = 0
    @State private var reps = 0
    @State private var hidden = false   // "recite from memory" — blur the text

    private var current: HifzAyah? { ayahs.indices.contains(index) ? ayahs[index] : nil }
    private var quranAyah: QuranAyah? {
        guard let c = current else { return nil }
        return QuranText.ayah(surah: c.surah, ayah: c.ayah)
    }

    var body: some View {
        VStack(spacing: 0) {
            progressBar
            ScrollView {
                VStack(spacing: 20) {
                    if let c = current {
                        headerLabel(c)
                        ayahCard(c)
                        audioAndReveal(c)
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
        VStack(spacing: 4) {
            ProgressView(value: Double(index), total: Double(max(1, ayahs.count)))
            Text("\(min(index + 1, ayahs.count)) of \(ayahs.count)")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal).padding(.top, 8)
    }

    private func headerLabel(_ c: HifzAyah) -> some View {
        HStack {
            Label("\(QuranData.surah(c.surah)?.transliteration ?? "Surah \(c.surah)") · Ayah \(c.ayah)",
                  systemImage: "text.book.closed")
                .font(.subheadline.weight(.medium))
            Spacer()
            Text("Page \(c.page)").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func ayahCard(_ c: HifzAyah) -> some View {
        arabic(for: c)
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

    /// Tajweed-coloured Arabic (falls back to plain text if the overlay is absent).
    private func arabic(for c: HifzAyah) -> Text {
        if let runs = TajweedText.runs(surah: c.surah, ayah: c.ayah) {
            return runs.reduce(Text("")) { acc, run in
                acc + Text(run.text).foregroundColor(run.rule?.color ?? .primary)
            }
        }
        return Text(quranAyah?.ar ?? "")
    }

    private func audioAndReveal(_ c: HifzAyah) -> some View {
        HStack(spacing: 12) {
            Button {
                audio.play(surah: c.surah, ayah: c.ayah)
            } label: {
                Label(audio.playingKey == c.key ? "Playing…" : "Listen to qari",
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
                Text("Repeated \(reps)×").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Button {
                    reps += 1
                    if let c = current { audio.play(surah: c.surah, ayah: c.ayah) }
                } label: { Label("Repeat aloud", systemImage: "repeat") }
                    .buttonStyle(.bordered)
                    .disabled(reps >= 10)
            }
            Text("Listen, then repeat 5–10× looking at the page. Hide it and recite from memory before confirming.")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 12) {
                Button(role: .destructive) { mistake() } label: {
                    Label("Mistake", systemImage: "xmark").frame(maxWidth: .infinity)
                }.buttonStyle(.bordered)
                Button { confirmFlawless() } label: {
                    Label("Flawless from memory", systemImage: "checkmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(reps < 3 || !hidden)
            }
        }
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

    private func confirmFlawless() {
        guard let c = current else { return }
        HifzProgramManager.confirmFlawless(c, state: state)
        try? context.save()
        next()
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

    private func next() {
        audio.stop()
        reps = 0
        hidden = false
        if index + 1 < ayahs.count {
            withAnimation { index += 1 }
        } else {
            onFinish()
            try? context.save()
            dismiss()
        }
    }
}
