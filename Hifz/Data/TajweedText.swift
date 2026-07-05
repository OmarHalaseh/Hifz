import SwiftUI
import CryptoKit

/// A tajweed rule, mapped from the single-letter codes in `quran-tajweed.json`.
/// Each rule carries a display name and a colour; several rules share a colour
/// *family* so the on-screen legend stays readable (see `TajweedRule.family`).
enum TajweedRule: String, CaseIterable {
    case hamzaWasl, silent, lamShamsiyah          // grey — not sounded / assimilated
    case maddNormal, maddPermissible              // blue — ordinary prolongation
    case maddNecessary, maddObligatory            // red  — long (4–6 count) prolongation
    case qalqalah                                 // green
    case ghunnah                                  // orange — nasalisation
    case ikhfa, ikhfaShafawi                      // purple
    case iqlab                                    // teal
    case idghamGhunnah, idghamNoGhunnah,
         idghamShafawi, idghamMutajanisayn, idghamMutaqaribayn  // pink — merging

    /// The code as it appears in the asset (`""` = no rule / plain text).
    init?(code: String) {
        switch code {
        case "h": self = .hamzaWasl
        case "s": self = .silent
        case "l": self = .lamShamsiyah
        case "n": self = .maddNormal
        case "p": self = .maddPermissible
        case "m": self = .maddNecessary
        case "o": self = .maddObligatory
        case "q": self = .qalqalah
        case "g": self = .ghunnah
        case "f": self = .ikhfa
        case "c": self = .ikhfaShafawi
        case "i": self = .iqlab
        case "a": self = .idghamGhunnah
        case "u": self = .idghamNoGhunnah
        case "w": self = .idghamShafawi
        case "d": self = .idghamMutajanisayn
        case "b": self = .idghamMutaqaribayn
        default:  return nil
        }
    }

    /// Colour family — the eight legend groups.
    enum Family: String, CaseIterable {
        case silent, madd, maddStrong, qalqalah, ghunnah, ikhfa, iqlab, idgham

        var color: Color {
            switch self {
            case .silent:     return Color(red: 0.60, green: 0.63, blue: 0.67) // grey
            case .madd:       return Color(red: 0.18, green: 0.44, blue: 0.93) // blue
            case .maddStrong: return Color(red: 0.84, green: 0.16, blue: 0.22) // red
            case .qalqalah:   return Color(red: 0.12, green: 0.62, blue: 0.29) // green
            case .ghunnah:    return Color(red: 0.91, green: 0.45, blue: 0.05) // orange
            case .ikhfa:      return Color(red: 0.56, green: 0.27, blue: 0.68) // purple
            case .iqlab:      return Color(red: 0.05, green: 0.60, blue: 0.65) // teal
            case .idgham:     return Color(red: 0.76, green: 0.16, blue: 0.54) // pink
            }
        }

        var label: String {
            switch self {
            case .silent:     return "Silent / assimilated"
            case .madd:       return "Prolongation (madd)"
            case .maddStrong: return "Long prolongation"
            case .qalqalah:   return "Qalqalah"
            case .ghunnah:    return "Ghunnah (nasalisation)"
            case .ikhfa:      return "Ikhfā"
            case .iqlab:      return "Iqlāb"
            case .idgham:     return "Idghām (merging)"
            }
        }
    }

    var family: Family {
        switch self {
        case .hamzaWasl, .silent, .lamShamsiyah:          return .silent
        case .maddNormal, .maddPermissible:               return .madd
        case .maddNecessary, .maddObligatory:             return .maddStrong
        case .qalqalah:                                   return .qalqalah
        case .ghunnah:                                    return .ghunnah
        case .ikhfa, .ikhfaShafawi:                       return .ikhfa
        case .iqlab:                                      return .iqlab
        case .idghamGhunnah, .idghamNoGhunnah, .idghamShafawi,
             .idghamMutajanisayn, .idghamMutaqaribayn:    return .idgham
        }
    }

    var color: Color { family.color }
}

/// One coloured segment of an ayah's tajweed text.
struct TajweedRun {
    let text: String
    let rule: TajweedRule?
}

/// Loads and exposes `quran-tajweed.json` — a companion colouring overlay for the
/// mushaf page view. It is deliberately separate from `QuranText`: the verified
/// Arabic origin of truth (`quran.json`) is never touched. If this asset is
/// missing the reader simply falls back to uncoloured text.
enum TajweedText {
    struct Meta: Codable {
        let edition: String
        let source: String
        let ayahCount: Int
        let runsSHA256: String
    }

    private struct AyahRuns: Codable {
        let n: Int
        let runs: [[String]]   // [[code, text], …]; code "" == plain
    }
    private struct SurahRuns: Codable {
        let number: Int
        let ayahs: [AyahRuns]
    }
    private struct Asset: Codable {
        let meta: Meta
        let surahs: [SurahRuns]
    }

    private static let asset: Asset? = {
        guard let url = Bundle.main.url(forResource: "quran-tajweed", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(Asset.self, from: data)
        else { return nil }
        return decoded
    }()

    /// Fast (surah, ayah) → runs index, built once.
    private static let index: [Int: [Int: [TajweedRun]]] = {
        guard let asset else { return [:] }
        var out: [Int: [Int: [TajweedRun]]] = [:]
        for s in asset.surahs {
            var ayahMap: [Int: [TajweedRun]] = [:]
            for a in s.ayahs {
                ayahMap[a.n] = a.runs.map { pair in
                    let code = pair.first ?? ""
                    let text = pair.count > 1 ? pair[1] : ""
                    return TajweedRun(text: text, rule: TajweedRule(code: code))
                }
            }
            out[s.number] = ayahMap
        }
        return out
    }()

    static var isAvailable: Bool { asset != nil }
    static var meta: Meta? { asset?.meta }

    /// Coloured runs for an ayah, or `nil` if the overlay isn't bundled.
    static func runs(surah: Int, ayah: Int) -> [TajweedRun]? {
        index[surah]?[ayah]
    }

    // MARK: - Integrity

    /// Re-hashes the loaded runs the same way `Tools/build_tajweed_asset.py` does,
    /// so a corrupt bundle is caught by a unit test.
    static func computedRunsSHA256() -> String? {
        guard let asset else { return nil }
        var lines: [String] = []
        for s in asset.surahs {
            for a in s.ayahs {
                var parts = "\(s.number)|\(a.n)|"
                for pair in a.runs {
                    let code = pair.first ?? ""
                    let text = pair.count > 1 ? pair[1] : ""
                    parts += "\(code)~\(text)|"
                }
                lines.append(parts)
            }
        }
        let canonical = lines.joined(separator: "\n")
        let digest = SHA256.hash(data: Data(canonical.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func verifyChecksum() -> Bool {
        guard let meta, let computed = computedRunsSHA256() else { return false }
        return computed == meta.runsSHA256
    }
}
