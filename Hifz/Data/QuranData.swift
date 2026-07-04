import Foundation

/// A trackable unit presented in the UI, independent of whether a progress row exists yet.
struct TrackUnit: Identifiable, Hashable {
    let key: String
    let granularity: Granularity
    let title: String
    let subtitle: String
    let arabic: String?
    let surahNumber: Int
    let pageNumber: Int
    let juzNumber: Int
    let ayahFrom: Int
    let ayahTo: Int

    var id: String { key }
}

/// Loads and exposes static Quran metadata plus the unit lists for each granularity.
enum QuranData {
    static let totalPages = 604
    static let totalJuz = 30

    /// Total ayahs in the Quran (Hafs), summed from the bundled metadata (6236).
    static let totalAyahs: Int = surahs.reduce(0) { $0 + $1.ayahCount }

    /// All 114 surahs, decoded once from the bundled JSON.
    static let surahs: [Surah] = {
        guard let url = Bundle.main.url(forResource: "surahs", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([Surah].self, from: data)
        else {
            assertionFailure("surahs.json missing or malformed")
            return []
        }
        return decoded.sorted { $0.number < $1.number }
    }()

    static func surah(_ number: Int) -> Surah? {
        surahs.first { $0.number == number }
    }

    /// The full set of trackable units for a granularity.
    /// Ayah-range units are user-created, so none are pre-generated.
    static func units(for granularity: Granularity) -> [TrackUnit] {
        switch granularity {
        case .surah:
            return surahs.map { s in
                TrackUnit(
                    key: MemorizationProgress.surahKey(s.number),
                    granularity: .surah,
                    title: "\(s.number). \(s.transliteration)",
                    subtitle: "\(s.nameEnglish) · \(s.ayahCount) ayahs · \(s.revelationPlace)",
                    arabic: s.nameArabic,
                    surahNumber: s.number,
                    pageNumber: 0, juzNumber: 0, ayahFrom: 0, ayahTo: 0
                )
            }
        case .juz:
            return (1...totalJuz).map { n in
                TrackUnit(
                    key: MemorizationProgress.juzKey(n),
                    granularity: .juz,
                    title: "Juz \(n)",
                    subtitle: "Part \(n) of \(totalJuz)",
                    arabic: nil,
                    surahNumber: 0, pageNumber: 0, juzNumber: n, ayahFrom: 0, ayahTo: 0
                )
            }
        case .page:
            return (1...totalPages).map { n in
                TrackUnit(
                    key: MemorizationProgress.pageKey(n),
                    granularity: .page,
                    title: "Page \(n)",
                    subtitle: "Page \(n) of \(totalPages)",
                    arabic: nil,
                    surahNumber: 0, pageNumber: n, juzNumber: 0, ayahFrom: 0, ayahTo: 0
                )
            }
        case .ayahRange:
            return []
        }
    }

    /// Rebuilds the display unit for an existing progress row.
    static func unit(for progress: MemorizationProgress) -> TrackUnit {
        switch progress.granularity {
        case .surah:
            return units(for: .surah).first { $0.surahNumber == progress.surahNumber }
                ?? placeholder(progress)
        case .juz:
            return units(for: .juz).first { $0.juzNumber == progress.juzNumber }
                ?? placeholder(progress)
        case .page:
            return units(for: .page).first { $0.pageNumber == progress.pageNumber }
                ?? placeholder(progress)
        case .ayahRange:
            return ayahUnit(surah: progress.surahNumber, from: progress.ayahFrom, to: progress.ayahTo)
        }
    }

    private static func placeholder(_ progress: MemorizationProgress) -> TrackUnit {
        TrackUnit(
            key: progress.unitKey, granularity: progress.granularity,
            title: progress.unitKey, subtitle: "", arabic: nil,
            surahNumber: progress.surahNumber, pageNumber: progress.pageNumber,
            juzNumber: progress.juzNumber, ayahFrom: progress.ayahFrom, ayahTo: progress.ayahTo
        )
    }

    /// Builds a TrackUnit describing an ayah range within a surah.
    static func ayahUnit(surah: Int, from: Int, to: Int) -> TrackUnit {
        let name = self.surah(surah)?.transliteration ?? "Surah \(surah)"
        return TrackUnit(
            key: MemorizationProgress.ayahKey(surah: surah, from: from, to: to),
            granularity: .ayahRange,
            title: "\(name) \(from)–\(to)",
            subtitle: "Ayahs \(from)–\(to)",
            arabic: self.surah(surah)?.nameArabic,
            surahNumber: surah, pageNumber: 0, juzNumber: 0, ayahFrom: from, ayahTo: to
        )
    }
}

extension MemorizationProgress {
    /// Creates a progress row that mirrors a TrackUnit's identity.
    convenience init(from unit: TrackUnit) {
        self.init(
            unitKey: unit.key,
            granularity: unit.granularity,
            surahNumber: unit.surahNumber,
            pageNumber: unit.pageNumber,
            juzNumber: unit.juzNumber,
            ayahFrom: unit.ayahFrom,
            ayahTo: unit.ayahTo
        )
    }
}
