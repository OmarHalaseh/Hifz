import Foundation

/// Static reference metadata for one surah, decoded from `surahs.json`.
struct Surah: Codable, Identifiable, Hashable {
    let number: Int
    let nameArabic: String
    let transliteration: String
    let nameEnglish: String
    let ayahCount: Int
    let revelationPlace: String   // "Makki" or "Madani"

    var id: Int { number }
    var isMakki: Bool { revelationPlace == "Makki" }
}
