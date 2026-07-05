import SwiftUI

/// A mushaf-style page reader: ayahs grouped by their real Madani page (1…604),
/// rendered as flowing right-to-left Uthmani text coloured by tajweed rule.
///
/// This is a page-grouped reading view, not a glyph-exact reproduction of the
/// printed KFGQPC mushaf (that needs per-page QCF fonts — the deferred P4 target).
/// Colours come from the `quran-tajweed` overlay; if that asset is missing the
/// text still renders, just uncoloured.
struct MushafPageView: View {
    @State private var page: Int
    @AppStorage("mushaf.arabicSize") private var arabicSize = 26.0
    @AppStorage("mushaf.tajweedOn") private var tajweedOn = true
    @State private var showLegend = false

    init(startPage: Int = 1) {
        _page = State(initialValue: min(max(1, startPage), QuranData.totalPages))
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(1...QuranData.totalPages, id: \.self) { p in
                    MushafPageContent(page: p, arabicSize: arabicSize, tajweedOn: tajweedOn)
                        .tag(p)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .environment(\.layoutDirection, .rightToLeft) // swipe like a real mushaf
            navigator
        }
        .navigationTitle("Page \(page) · Juz \(juz(of: page))")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Toggle("Tajweed colours", isOn: $tajweedOn)
                    Button { showLegend = true } label: { Label("Colour legend", systemImage: "paintpalette") }
                    Divider()
                    Button { arabicSize = min(40, arabicSize + 2) } label: { Label("Larger", systemImage: "textformat.size.larger") }
                    Button { arabicSize = max(18, arabicSize - 2) } label: { Label("Smaller", systemImage: "textformat.size.smaller") }
                } label: {
                    Image(systemName: "textformat.size")
                }
            }
        }
        .sheet(isPresented: $showLegend) { TajweedLegendView() }
        .background(MushafTheme.pageBackground.ignoresSafeArea())
    }

    /// Bottom page navigator — a slider that scrubs across the whole mushaf.
    private var navigator: some View {
        HStack(spacing: 12) {
            Text("1").font(.caption2).foregroundStyle(.secondary)
            Slider(
                value: Binding(get: { Double(page) }, set: { page = Int($0.rounded()) }),
                in: 1...Double(QuranData.totalPages), step: 1
            )
            Text("\(QuranData.totalPages)").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func juz(of page: Int) -> Int {
        QuranText.ayahs(onPage: page).map(\.ayah.juz).min() ?? 1
    }
}

private enum MushafTheme {
    static var pageBackground: Color {
        Color(uiColor: UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(white: 0.09, alpha: 1)
                : UIColor(red: 0.99, green: 0.975, blue: 0.92, alpha: 1) // warm parchment
        })
    }
}

/// One rendered mushaf page.
private struct MushafPageContent: View {
    let page: Int
    let arabicSize: Double
    let tajweedOn: Bool

    /// Consecutive same-surah slices of this page.
    private struct Group: Identifiable {
        let id = UUID()
        let surah: Int
        let ayahs: [QuranAyah]
        var startsSurah: Bool { ayahs.first?.n == 1 }
    }

    private var groups: [Group] {
        var result: [Group] = []
        for (surah, ayah) in QuranText.ayahs(onPage: page) {
            if let last = result.last, last.surah == surah {
                result[result.count - 1] = Group(surah: surah, ayahs: last.ayahs + [ayah])
            } else {
                result.append(Group(surah: surah, ayahs: [ayah]))
            }
        }
        return result
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                ForEach(groups) { group in
                    if group.startsSurah {
                        SurahBanner(surah: group.surah)
                        if group.surah != 1 && group.surah != 9 {
                            basmala
                        }
                    }
                    flowing(for: group)
                }
                Text("\(page)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
        }
    }

    private var basmala: some View {
        coloredText(runs: TajweedText.runs(surah: 1, ayah: 1),
                    fallback: QuranText.ayah(surah: 1, ayah: 1)?.ar ?? "",
                    size: arabicSize * 0.82, includeMarker: false, ayahNumber: 0)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 2)
    }

    /// Flowing, justified text for a whole surah-slice, ayah markers inline.
    private func flowing(for group: Group) -> some View {
        var text = Text("")
        for ayah in group.ayahs {
            text = text + segment(surah: group.surah, ayah: ayah)
        }
        return text
            .font(.system(size: arabicSize, weight: .regular))
            .lineSpacing(arabicSize * 0.55)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .environment(\.layoutDirection, .rightToLeft)
    }

    private func segment(surah: Int, ayah: QuranAyah) -> Text {
        var t = Text("")
        if tajweedOn, let runs = TajweedText.runs(surah: surah, ayah: ayah.n) {
            for run in runs {
                t = t + Text(run.text).foregroundColor(run.rule?.color ?? .primary)
            }
        } else {
            t = t + Text(ayah.ar).foregroundColor(.primary)
        }
        return t + ayahMarker(ayah.n)
    }

    private func ayahMarker(_ n: Int) -> Text {
        Text(" ﴿\(arabicDigits(n))﴾ ")
            .foregroundColor(.secondary)
            .font(.system(size: arabicSize * 0.72))
    }

    /// Helper used only for the basmala header (no marker).
    private func coloredText(runs: [TajweedRun]?, fallback: String, size: Double,
                             includeMarker: Bool, ayahNumber: Int) -> some View {
        var t = Text("")
        if tajweedOn, let runs {
            for run in runs { t = t + Text(run.text).foregroundColor(run.rule?.color ?? .primary) }
        } else {
            t = t + Text(fallback).foregroundColor(.primary)
        }
        return t
            .font(.system(size: size, weight: .regular))
            .lineSpacing(size * 0.5)
            .multilineTextAlignment(.center)
            .environment(\.layoutDirection, .rightToLeft)
    }
}

/// Ornamental surah header band.
private struct SurahBanner: View {
    let surah: Int
    private var meta: Surah? { QuranData.surah(surah) }

    var body: some View {
        HStack {
            Image(systemName: "leaf").font(.caption).foregroundStyle(.tint.opacity(0.6))
            Spacer()
            VStack(spacing: 2) {
                Text(meta?.nameArabic ?? "")
                    .font(.system(size: 22, weight: .semibold))
                    .environment(\.layoutDirection, .rightToLeft)
                Text("\(meta?.transliteration ?? "") · \(meta.map { "\($0.ayahCount) ayahs" } ?? "")")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "leaf").font(.caption).foregroundStyle(.tint.opacity(0.6))
                .scaleEffect(x: -1)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.tint.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.tint.opacity(0.25), lineWidth: 1))
        )
    }
}

/// The tajweed colour key.
struct TajweedLegendView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(TajweedRule.Family.allCases, id: \.self) { family in
                        HStack(spacing: 14) {
                            Circle().fill(family.color).frame(width: 18, height: 18)
                            Text(family.label)
                            Spacer()
                        }
                    }
                } footer: {
                    Text("Letters are coloured by their tajweed rule so recitation points stand out. Colouring is a study aid; recite with a qualified teacher.")
                }
            }
            .navigationTitle("Tajweed colours")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// Western digits → Arabic-Indic digits (٠١٢…).
func arabicDigits(_ n: Int) -> String {
    let map: [Character: Character] = ["0": "٠", "1": "١", "2": "٢", "3": "٣", "4": "٤",
                                       "5": "٥", "6": "٦", "7": "٧", "8": "٨", "9": "٩"]
    return String(String(n).map { map[$0] ?? $0 })
}
