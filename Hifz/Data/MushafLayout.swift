import Foundation
import CryptoKit

/// A memorization portion size expressed in mushaf terms. This is how much *new*
/// material one Sabaq covers, and the granularity the general tracker can bucket
/// by. Row is the atom (one printed line); the rest are groups of consecutive
/// text lines on a page.
enum MushafUnitKind: String, Codable, CaseIterable, Identifiable {
    case row        // one printed line
    case quarter    // ~quarter page
    case half       // ~half page
    case page       // a whole page

    var id: String { rawValue }

    /// How many portions a full 15-line page splits into.
    var portionsPerPage: Int {
        switch self {
        case .row: return 15
        case .quarter: return 4
        case .half: return 2
        case .page: return 1
        }
    }

    /// Nominal text-line count of one portion — the base Sabaq size in lines.
    var baseLines: Int {
        switch self {
        case .row: return 1
        case .quarter: return 4
        case .half: return 8
        case .page: return 15
        }
    }

    var label: String {
        switch self {
        case .row: return "Row (line)"
        case .quarter: return "Quarter page"
        case .half: return "Half page"
        case .page: return "Page"
        }
    }

    var shortLabel: String {
        switch self {
        case .row: return "Row"
        case .quarter: return "¼ page"
        case .half: return "½ page"
        case .page: return "Page"
        }
    }
}

/// One line of the printed KFGQPC Madani mushaf (`mushaf-layout.json`, built by
/// `Tools/build_mushaf_layout.py`). Field names are terse to keep the asset small.
struct MushafLine: Codable, Hashable {
    /// Line number within the page (1…15).
    let l: Int
    /// Kind: "h" surah header, "b" basmala, "t" ayah text.
    let k: String
    /// Surah number — set only on header lines.
    let s: Int?
    /// Ayah segments as `[surah, ayah, wordFrom, wordTo]`, in reading order.
    let segs: [[Int]]?
    /// The printed line text (ayah lines only).
    let t: String?

    var isText: Bool { k == "t" }
    var isSurahHeader: Bool { k == "h" }
    var isBasmala: Bool { k == "b" }

    var text: String { t ?? "" }
    var headerSurah: Int? { s }

    /// One ayah-fragment covered by a text line.
    struct Segment: Hashable {
        let surah: Int
        let ayah: Int
        let wordFrom: Int
        let wordTo: Int
    }

    var segments: [Segment] {
        (segs ?? []).compactMap { a in
            a.count == 4 ? Segment(surah: a[0], ayah: a[1], wordFrom: a[2], wordTo: a[3]) : nil
        }
    }

    /// The surah a text line primarily belongs to (its first segment's surah).
    var primarySurah: Int? { segments.first?.surah }
}

/// A resolved atom of the ḥifẓ program: one text line at a known page position.
struct MushafLineRef: Hashable, Identifiable {
    let page: Int
    let line: MushafLine
    var id: String { MushafLineRef.key(page: page, line: line.l) }
    var lineNumber: Int { line.l }
    static func key(page: Int, line: Int) -> String { "\(page):\(line)" }
}

/// One trackable portion (row / quarter / half / page) on a page — a contiguous
/// run of text lines.
struct MushafPortion: Identifiable, Hashable {
    let page: Int
    let index: Int          // 1-based within the page for this unit kind
    let lines: [MushafLine] // the text lines it covers
    var lineFrom: Int { lines.first?.l ?? 0 }
    var lineTo: Int { lines.last?.l ?? 0 }
    var id: String { "\(page):\(index):\(lineFrom)-\(lineTo)" }
}

/// Loads and exposes the verified KFGQPC 15-line mushaf layout.
///
/// The asset's provenance and checksum live in `meta`; `verifyChecksum()`
/// re-hashes the loaded layout and is asserted by a unit test so bundle
/// corruption is caught — mirrors `QuranText`.
enum MushafLayout {
    struct Meta: Codable {
        let mushaf: String
        let layoutOrigin: String
        let layoutSource: String
        let pageNumbering: String
        let pages: Int
        let totalLines: Int
        let layoutSHA256: String
    }

    struct Page: Codable, Identifiable {
        let p: Int
        let lines: [MushafLine]
        var id: Int { p }
    }

    private struct Asset: Codable {
        let meta: Meta
        let pages: [Page]
    }

    private static let asset: Asset = {
        guard let url = Bundle.main.url(forResource: "mushaf-layout", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(Asset.self, from: data)
        else {
            assertionFailure("mushaf-layout.json missing or malformed")
            return Asset(meta: Meta(mushaf: "", layoutOrigin: "", layoutSource: "",
                                    pageNumbering: "", pages: 0, totalLines: 0, layoutSHA256: ""),
                         pages: [])
        }
        return decoded
    }()

    static var meta: Meta { asset.meta }
    static var totalPages: Int { asset.pages.count }

    private static let pageIndex: [Int: Page] = {
        Dictionary(uniqueKeysWithValues: asset.pages.map { ($0.p, $0) })
    }()

    /// Every line on a page (headers, basmala, text) in print order.
    static func lines(onPage page: Int) -> [MushafLine] { pageIndex[page]?.lines ?? [] }

    /// Only the memorizable text lines of a page, in order.
    static func textLines(onPage page: Int) -> [MushafLine] {
        lines(onPage: page).filter(\.isText)
    }

    static func line(page: Int, line: Int) -> MushafLine? {
        lines(onPage: page).first { $0.l == line }
    }

    /// Total memorizable text lines across the whole mushaf.
    static var totalTextLines: Int {
        asset.pages.reduce(0) { $0 + $1.lines.filter(\.isText).count }
    }

    /// Every text line in mushaf order — the atom source for the ḥifẓ program.
    static var orderedTextLines: [MushafLineRef] {
        asset.pages
            .sorted { $0.p < $1.p }
            .flatMap { pg in pg.lines.filter(\.isText).map { MushafLineRef(page: pg.p, line: $0) } }
    }

    /// The portions a page splits into for a given unit kind (contiguous runs of
    /// text lines). Row → one portion per text line; the rest chunk the page's
    /// text lines into nearly-equal contiguous groups.
    static func portions(onPage page: Int, kind: MushafUnitKind) -> [MushafPortion] {
        let text = textLines(onPage: page)
        guard !text.isEmpty else { return [] }
        if kind == .row {
            return text.enumerated().map { MushafPortion(page: page, index: $0.offset + 1, lines: [$0.element]) }
        }
        let parts = min(kind.portionsPerPage, text.count)
        var result: [MushafPortion] = []
        let n = text.count
        var start = 0
        for i in 0..<parts {
            // distribute the remainder across the first chunks
            let remaining = n - start
            let size = Int((Double(remaining) / Double(parts - i)).rounded())
            let slice = Array(text[start..<min(start + max(1, size), n)])
            result.append(MushafPortion(page: page, index: i + 1, lines: slice))
            start += slice.count
            if start >= n { break }
        }
        return result
    }

    // MARK: - Integrity

    /// The canonical string the asset's SHA-256 is computed over. Must exactly
    /// mirror `Tools/build_mushaf_layout.py` (`canonical`).
    private static var canonical: String {
        var out: [String] = []
        for pg in asset.pages.sorted(by: { $0.p < $1.p }) {
            for ln in pg.lines {
                switch ln.k {
                case "h": out.append("\(pg.p)|\(ln.l)|h|\(ln.s ?? 0)")
                case "b": out.append("\(pg.p)|\(ln.l)|b|")
                default:
                    let segs = ln.segments.map { "\($0.surah):\($0.ayah):\($0.wordFrom):\($0.wordTo)" }
                        .joined(separator: ",")
                    out.append("\(pg.p)|\(ln.l)|t|\(segs)|\(ln.text)")
                }
            }
        }
        return out.joined(separator: "\n")
    }

    static func computedLayoutSHA256() -> String {
        let digest = SHA256.hash(data: Data(canonical.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// True when the bundled layout still hashes to the checksum recorded at build time.
    static func verifyChecksum() -> Bool {
        computedLayoutSHA256() == meta.layoutSHA256
    }
}
