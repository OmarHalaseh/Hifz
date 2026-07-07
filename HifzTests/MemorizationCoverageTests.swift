import XCTest
@testable import Hifz

/// Verifies the unified progress layer: a track unit's effective status is a
/// *union* of the ḥifẓ program's ayah coverage and any manual mark.
final class MemorizationCoverageTests: XCTestCase {

    /// Al-Fātiḥa — surah 1, 7 ayahs, the first page of the Madani mushaf.
    private var fatiha: TrackUnit {
        QuranData.units(for: .surah).first { $0.surahNumber == 1 }!
    }
    private var fatihaKeys: Set<String> { Set((1...7).map { "1:\($0)" }) }

    func testAyahKeysMatchSurahLength() {
        XCTAssertEqual(MemorizationCoverage.ayahKeys(in: fatiha).count, 7)
        XCTAssertEqual(Set(MemorizationCoverage.ayahKeys(in: fatiha)), fatihaKeys)
    }

    func testFullProgramCoverageIsMemorized() {
        XCTAssertEqual(
            MemorizationCoverage.status(for: fatiha, memorizedKeys: fatihaKeys, stored: nil),
            .memorized
        )
    }

    func testPartialProgramCoverageIsLearning() {
        XCTAssertEqual(
            MemorizationCoverage.status(for: fatiha, memorizedKeys: ["1:1", "1:2"], stored: nil),
            .learning
        )
    }

    func testManualMarkCountsWithoutAyahRows() {
        // A surah marked memorized by hand, with no HifzAyah rows, still reads memorized.
        XCTAssertEqual(
            MemorizationCoverage.status(for: fatiha, memorizedKeys: [], stored: .memorized),
            .memorized
        )
        // And a manual "learning" mark surfaces as learning.
        XCTAssertEqual(
            MemorizationCoverage.status(for: fatiha, memorizedKeys: [], stored: .learning),
            .learning
        )
    }

    func testNoCoverageIsNotStarted() {
        XCTAssertEqual(
            MemorizationCoverage.status(for: fatiha, memorizedKeys: [], stored: nil),
            .notStarted
        )
        XCTAssertEqual(
            MemorizationCoverage.status(for: fatiha, memorizedKeys: [], stored: .notStarted),
            .notStarted
        )
    }

    func testStatusCountsAggregateAcrossGranularity() {
        let units = QuranData.units(for: .surah)
        let counts = MemorizationCoverage.statusCounts(
            units: units, memorizedKeys: fatihaKeys, stored: [:]
        )
        XCTAssertEqual(counts.memorized, 1, "Only surah 1 is fully covered.")
        XCTAssertEqual(counts.learning, 0)
        XCTAssertEqual(counts.notStarted, units.count - 1)
        XCTAssertEqual(counts.memorized + counts.learning + counts.notStarted, units.count)
    }

    func testPageMembershipUsesRealLayout() {
        // Page 1 of the Madani mushaf is al-Fātiḥa.
        let page1 = QuranData.units(for: .page).first { $0.pageNumber == 1 }!
        let keys = MemorizationCoverage.ayahKeys(in: page1)
        XCTAssertFalse(keys.isEmpty)
        XCTAssertTrue(keys.contains("1:1"))
    }

    func testLineUnitAyahsAreSubsetOfItsPage() {
        guard let lineUnit = QuranData.units(for: .line).first(where: { $0.pageNumber == 2 }) else {
            return XCTFail("expected line units on page 2")
        }
        let lineKeys = Set(MemorizationCoverage.ayahKeys(in: lineUnit))
        let pageKeys = Set(MemorizationCoverage.ayahKeys(
            in: QuranData.units(for: .page).first { $0.pageNumber == 2 }!
        ))
        XCTAssertFalse(lineKeys.isEmpty)
        XCTAssertTrue(lineKeys.isSubset(of: pageKeys), "a row's ayahs must belong to its page")
    }
}
