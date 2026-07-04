import XCTest
@testable import Hifz

/// Integrity gate for the A1 reference asset. If any of these fail, the bundled
/// Quran text has changed or been corrupted — treat that as release-blocking.
final class QuranAssetTests: XCTestCase {

    /// The Arabic SHA-256 recorded when `Tools/build_quran_asset.py` verified the
    /// text against the Tanzil origin + independent cross-check. Pinning it here
    /// means the text can never silently change under us.
    private let pinnedArabicSHA256 = "c48c081b3bd3f7b3d9ebc4e14340ee01de6ef4480b7e4ecc9f25caf039131965"

    private func requireAsset() throws {
        try XCTSkipIf(QuranText.meta.ayahCount == 0, "quran.json not available in test bundle")
    }

    func testAssetLoadsAllAyahs() throws {
        try requireAsset()
        XCTAssertEqual(QuranText.meta.ayahCount, 6236)
        XCTAssertEqual(QuranText.surahs.count, 114)
        XCTAssertEqual(QuranText.surahs.reduce(0) { $0 + $1.ayahs.count }, 6236)
    }

    func testChecksumMatchesRecordedAndPinned() throws {
        try requireAsset()
        XCTAssertTrue(QuranText.verifyChecksum(), "bundled Arabic no longer matches its embedded checksum")
        XCTAssertEqual(QuranText.computedArabicSHA256(), pinnedArabicSHA256,
                       "Arabic text changed vs the verified Tanzil build")
        XCTAssertEqual(QuranText.meta.arabicSHA256, pinnedArabicSHA256)
    }

    func testPerSurahCountsMatchMetadata() throws {
        try requireAsset()
        for surah in QuranData.surahs {
            XCTAssertEqual(QuranText.ayahs(surah: surah.number).count, surah.ayahCount,
                           "surah \(surah.number) ayah count mismatch")
        }
    }

    func testPageAndJuzCoverage() throws {
        try requireAsset()
        let pages = Set(QuranText.surahs.flatMap { $0.ayahs.map(\.page) })
        XCTAssertEqual(pages.min(), 1)
        XCTAssertEqual(pages.max(), 604)
        let juz = Set(QuranText.surahs.flatMap { $0.ayahs.map(\.juz) })
        XCTAssertEqual(juz.min(), 1)
        XCTAssertEqual(juz.max(), 30)
        XCTAssertEqual(QuranText.ayah(surah: 1, ayah: 1)?.page, 1)
        XCTAssertEqual(QuranText.ayah(surah: 2, ayah: 1)?.juz, 1)
    }

    func testFatihaOpensWithBasmala() throws {
        try requireAsset()
        let a = try XCTUnwrap(QuranText.ayah(surah: 1, ayah: 1))
        // Avoid brittle diacritic-exact Arabic matching; check robust invariants.
        XCTAssertFalse(a.ar.isEmpty)
        XCTAssertTrue(a.ar.unicodeScalars.contains { ("\u{0600}"..."\u{06FF}").contains($0) },
                      "first ayah should contain Arabic script")
        XCTAssertTrue(a.en.localizedCaseInsensitiveContains("name of Allah"),
                      "1:1 Saheeh translation begins 'In the name of Allah…'")
        XCTAssertFalse(a.tr.isEmpty)
    }
}
