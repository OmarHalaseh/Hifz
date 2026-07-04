import Foundation
import CryptoKit

/// One ayah of the bundled reference text (`quran.json`, built by
/// `Tools/build_quran_asset.py`). Field names are terse to keep the 3 MB asset small.
struct QuranAyah: Codable, Identifiable, Hashable {
    let n: Int          // ayah number within the surah
    let ar: String      // Uthmani Arabic (Tanzil origin)
    let en: String      // Saheeh International translation
    let tr: String      // English transliteration
    let juz: Int
    let page: Int       // Madani mushaf page (1…604)
    let sajda: Bool?

    var id: Int { n }
    var isSajda: Bool { sajda == true }
}

struct QuranSurahText: Codable, Identifiable {
    let number: Int
    let ayahs: [QuranAyah]
    var id: Int { number }
}

/// Loads and exposes the verified Quran text asset.
///
/// The asset's provenance and checksum live in `meta`; `verifyChecksum()` re-hashes
/// the loaded Arabic and is asserted by a unit test so bundle corruption is caught.
enum QuranText {
    struct Meta: Codable {
        let arabicEdition: String
        let arabicSource: String
        let translation: String
        let transliteration: String
        let mushaf: String
        let pageNumbering: String
        let ayahCount: Int
        let arabicSHA256: String
    }

    private struct Asset: Codable {
        let meta: Meta
        let surahs: [QuranSurahText]
    }

    private static let asset: Asset = {
        guard let url = Bundle.main.url(forResource: "quran", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(Asset.self, from: data)
        else {
            assertionFailure("quran.json missing or malformed")
            return Asset(meta: Meta(arabicEdition: "", arabicSource: "", translation: "",
                                    transliteration: "", mushaf: "", pageNumbering: "",
                                    ayahCount: 0, arabicSHA256: ""), surahs: [])
        }
        return decoded
    }()

    static var meta: Meta { asset.meta }
    static var surahs: [QuranSurahText] { asset.surahs }

    static func ayahs(surah: Int) -> [QuranAyah] {
        asset.surahs.first { $0.number == surah }?.ayahs ?? []
    }

    static func ayah(surah: Int, ayah: Int) -> QuranAyah? {
        ayahs(surah: surah).first { $0.n == ayah }
    }

    /// All ayahs on a given Madani page, in order — used for page-based reading.
    static func ayahs(onPage page: Int) -> [(surah: Int, ayah: QuranAyah)] {
        asset.surahs.flatMap { s in s.ayahs.filter { $0.page == page }.map { (s.number, $0) } }
    }

    // MARK: - Integrity

    /// The canonical string the asset's SHA-256 is computed over. Must exactly
    /// mirror `Tools/build_quran_asset.py` (`"sura|aya|text"` lines, ayah order).
    private static var canonicalArabic: String {
        asset.surahs
            .sorted { $0.number < $1.number }
            .flatMap { s in s.ayahs.sorted { $0.n < $1.n }.map { "\(s.number)|\($0.n)|\($0.ar)" } }
            .joined(separator: "\n")
    }

    static func computedArabicSHA256() -> String {
        let digest = SHA256.hash(data: Data(canonicalArabic.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// True when the bundled Arabic still hashes to the checksum recorded at build time.
    static func verifyChecksum() -> Bool {
        computedArabicSHA256() == meta.arabicSHA256
    }
}
