import SwiftUI
import SwiftData

/// Read-only projection: is this ayah covered by any memorized unit, at whatever
/// granularity the user tracks? Uses the A1 ayah→juz/page map, so it works across
/// granularities without any schema change. (Reader write-actions are intentionally
/// deferred until the parallel-vs-atomic data-model decision at B1.)
enum ReaderCoverage {
    static func isMemorized(surah: Int, ayah: QuranAyah, progress: [MemorizationProgress]) -> Bool {
        progress.contains { p in
            guard p.status == .memorized else { return false }
            switch p.granularity {
            case .surah:     return p.surahNumber == surah
            case .juz:       return p.juzNumber == ayah.juz
            case .page:      return p.pageNumber == ayah.page
            case .halfPage, .quarterPage, .line:
                // Page-portion units cover a specific line range; the ayah is
                // memorized only if one of those printed lines carries it.
                guard p.pageNumber == ayah.page else { return false }
                return MushafLayout.lines(onPage: p.pageNumber)
                    .filter { p.lineFrom <= $0.l && $0.l <= p.lineTo }
                    .contains { $0.segments.contains { $0.surah == surah && $0.ayah == ayah.n } }
            case .ayahRange: return p.surahNumber == surah && p.ayahFrom <= ayah.n && ayah.n <= p.ayahTo
            }
        }
    }
}

/// Browsable index of all 114 surahs for reading.
struct ReaderIndexView: View {
    @State private var search = ""

    private var results: [Surah] {
        guard !search.isEmpty else { return QuranData.surahs }
        return QuranData.surahs.filter {
            $0.transliteration.localizedCaseInsensitiveContains(search)
            || $0.nameEnglish.localizedCaseInsensitiveContains(search)
            || $0.nameArabic.contains(search)
            || String($0.number) == search
        }
    }

    var body: some View {
        List(results) { surah in
            NavigationLink {
                SurahReaderView(surahNumber: surah.number)
            } label: {
                HStack(spacing: 12) {
                    Text("\(surah.number)")
                        .font(.subheadline.monospacedDigit().weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(surah.transliteration).font(.body.weight(.medium))
                        Text("\(surah.nameEnglish) · \(surah.ayahCount) ayahs").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(surah.nameArabic)
                        .font(.system(size: 20, weight: .semibold))
                        .environment(\.layoutDirection, .rightToLeft)
                }
                .padding(.vertical, 2)
            }
        }
        .listStyle(.plain)
        .navigationTitle("Read Qur'an")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Surah")
    }
}

/// Reads a single surah: Uthmani Arabic with optional transliteration + translation,
/// and a memorized indicator per ayah.
struct SurahReaderView: View {
    let surahNumber: Int
    var scrollTo: Int? = nil

    @Query private var allProgress: [MemorizationProgress]

    @AppStorage("reader.showTranslation") private var showTranslation = true
    @AppStorage("reader.showTransliteration") private var showTransliteration = true
    @AppStorage("reader.arabicSize") private var arabicSize = 30.0

    private var surah: Surah? { QuranData.surah(surahNumber) }
    private var ayahs: [QuranAyah] { QuranText.ayahs(surah: surahNumber) }

    // Basmala shown as a header for every surah except Al-Fatiha (where it is
    // ayah 1) and At-Tawbah (which has none).
    private var showsBasmalaHeader: Bool { surahNumber != 1 && surahNumber != 9 }
    private var basmala: String { QuranText.ayah(surah: 1, ayah: 1)?.ar ?? "" }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if showsBasmalaHeader && !basmala.isEmpty {
                        Text(basmala)
                            .font(.system(size: arabicSize * 0.8, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .environment(\.layoutDirection, .rightToLeft)
                            .padding(.vertical, 16)
                    }
                    ForEach(ayahs) { ayah in
                        AyahView(
                            surahNumber: surahNumber,
                            ayah: ayah,
                            arabicSize: arabicSize,
                            showTransliteration: showTransliteration,
                            showTranslation: showTranslation,
                            memorized: ReaderCoverage.isMemorized(surah: surahNumber, ayah: ayah, progress: allProgress)
                        )
                        .id(ayah.n)
                        Divider()
                    }
                }
                .padding(.horizontal)
            }
            .onAppear {
                if let target = scrollTo {
                    proxy.scrollTo(target, anchor: .top)
                }
            }
        }
        .navigationTitle(surah.map { "\($0.number). \($0.transliteration)" } ?? "Surah \(surahNumber)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Toggle("Translation", isOn: $showTranslation)
                    Toggle("Transliteration", isOn: $showTransliteration)
                    Divider()
                    Button { arabicSize = min(48, arabicSize + 2) } label: { Label("Larger Arabic", systemImage: "textformat.size.larger") }
                    Button { arabicSize = max(20, arabicSize - 2) } label: { Label("Smaller Arabic", systemImage: "textformat.size.smaller") }
                } label: {
                    Image(systemName: "textformat.size")
                }
            }
        }
    }
}

private struct AyahView: View {
    let surahNumber: Int
    let ayah: QuranAyah
    let arabicSize: Double
    let showTransliteration: Bool
    let showTranslation: Bool
    let memorized: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("\(ayah.n)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tint)
                    .frame(minWidth: 26, minHeight: 26)
                    .background(Circle().fill(.tint.opacity(0.12)))
                if ayah.isSajda {
                    Label("Sajda", systemImage: "figure.bow").font(.caption2).foregroundStyle(.orange)
                }
                Spacer()
                if memorized {
                    Image(systemName: "checkmark.seal.fill").font(.footnote).foregroundStyle(.green)
                }
            }

            Text(ayah.ar)
                .font(.system(size: arabicSize, weight: .medium))
                .lineSpacing(arabicSize * 0.5)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .multilineTextAlignment(.trailing)
                .environment(\.layoutDirection, .rightToLeft)

            if showTransliteration {
                Text(ayah.tr)
                    .font(.callout.italic())
                    .foregroundStyle(.secondary)
            }
            if showTranslation {
                Text(ayah.en)
                    .font(.footnote)
                    .foregroundStyle(.primary.opacity(0.8))
            }
        }
        .padding(.vertical, 14)
        .contextMenu {
            Button { UIPasteboard.general.string = ayah.ar } label: { Label("Copy Arabic", systemImage: "doc.on.doc") }
            Button { UIPasteboard.general.string = ayah.en } label: { Label("Copy translation", systemImage: "doc.on.doc") }
        }
    }
}
