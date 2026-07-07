import XCTest
@testable import Hifz

/// Integrity gate for the mushaf line-layout asset (`mushaf-layout.json`, built by
/// `Tools/build_mushaf_layout.py`). This is the line data the row/quarter/half/page
/// memorization units depend on; corruption here is release-blocking.
final class MushafLayoutTests: XCTestCase {

    /// The layout SHA-256 recorded when the builder verified page coverage against
    /// quran.json. Pinning it means the layout can never silently change under us.
    private let pinnedLayoutSHA256 = "5ba39fe9a19fa510cae01f94453de936e01f8068567df913e15cab35e962febd"

    private func requireAsset() throws {
        try XCTSkipIf(MushafLayout.totalPages == 0, "mushaf-layout.json not available in test bundle")
    }

    func testLoadsAll604Pages() throws {
        try requireAsset()
        XCTAssertEqual(MushafLayout.totalPages, 604)
        XCTAssertEqual(MushafLayout.meta.pages, 604)
        XCTAssertEqual(MushafLayout.totalTextLines, MushafLayout.meta.totalLines - surahHeaderAndBasmalaCount())
    }

    func testChecksumMatchesRecordedAndPinned() throws {
        try requireAsset()
        XCTAssertTrue(MushafLayout.verifyChecksum(), "bundled layout no longer matches its embedded checksum")
        XCTAssertEqual(MushafLayout.computedLayoutSHA256(), pinnedLayoutSHA256,
                       "layout changed vs the verified build")
        XCTAssertEqual(MushafLayout.meta.layoutSHA256, pinnedLayoutSHA256)
    }

    /// Every text line's segments are contiguous, and a page's segments cover
    /// exactly the ayahs quran.json places on that page (same invariant the
    /// builder enforced, re-checked at runtime against the shipped assets).
    func testPageCoverageMatchesQuranText() throws {
        try requireAsset()
        try XCTSkipIf(QuranText.meta.ayahCount == 0, "quran.json not available")
        for page in 1...604 {
            var layoutAyahs = Set<String>()
            for line in MushafLayout.textLines(onPage: page) {
                for seg in line.segments {
                    XCTAssertLessThanOrEqual(seg.wordFrom, seg.wordTo, "page \(page) line \(line.l) bad word range")
                    layoutAyahs.insert("\(seg.surah):\(seg.ayah)")
                }
            }
            let quranAyahs = Set(QuranText.ayahs(onPage: page).map { "\($0.surah):\($0.ayah.n)" })
            XCTAssertEqual(layoutAyahs, quranAyahs, "page \(page) ayah coverage differs from quran.json")
        }
    }

    func testPortionsSplitTextLines() throws {
        try requireAsset()
        // A typical full page (15 text lines): row → 15, quarter → 4, half → 2, page → 1.
        let full = (1...604).first { MushafLayout.textLines(onPage: $0).count == 15 }!
        XCTAssertEqual(MushafLayout.portions(onPage: full, kind: .row).count, 15)
        XCTAssertEqual(MushafLayout.portions(onPage: full, kind: .quarter).count, 4)
        XCTAssertEqual(MushafLayout.portions(onPage: full, kind: .half).count, 2)
        XCTAssertEqual(MushafLayout.portions(onPage: full, kind: .page).count, 1)

        // Portions partition the page's text lines with no gaps or overlaps.
        for kind in MushafUnitKind.allCases {
            let covered = MushafLayout.portions(onPage: full, kind: kind).flatMap { $0.lines.map(\.l) }
            XCTAssertEqual(covered.sorted(), MushafLayout.textLines(onPage: full).map(\.l),
                           "\(kind) portions must cover every text line exactly once")
        }
    }

    func testOrderedTextLinesAreInMushafOrder() throws {
        try requireAsset()
        let refs = MushafLayout.orderedTextLines
        XCTAssertEqual(refs.count, MushafLayout.totalTextLines)
        for (a, b) in zip(refs, refs.dropFirst()) {
            XCTAssertTrue((a.page, a.lineNumber) <= (b.page, b.lineNumber), "atoms not in mushaf order")
        }
    }

    private func surahHeaderAndBasmalaCount() -> Int {
        (1...604).reduce(0) { acc, p in
            acc + MushafLayout.lines(onPage: p).filter { !$0.isText }.count
        }
    }
}
