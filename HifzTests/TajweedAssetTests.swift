import XCTest
@testable import Hifz

/// Guards the companion tajweed overlay (`quran-tajweed.json`). The SHA is pinned
/// so bundle corruption or an accidental re-build is caught; regenerate with
/// `python3 Tools/build_tajweed_asset.py` and re-pin here if it legitimately changes.
final class TajweedAssetTests: XCTestCase {

    /// Pinned by Tools/build_tajweed_asset.py (runsSHA256).
    private let pinnedSHA = "d0a425a80ea12f309c7b86ce6b1013cbcffba883ae33963c18be241dcc1dfb5d"

    func testAssetIsBundled() {
        XCTAssertTrue(TajweedText.isAvailable, "quran-tajweed.json should be bundled")
        XCTAssertEqual(TajweedText.meta?.ayahCount, 6236)
    }

    func testChecksumMatchesPinnedValue() {
        XCTAssertEqual(TajweedText.meta?.runsSHA256, pinnedSHA)
        XCTAssertEqual(TajweedText.computedRunsSHA256(), pinnedSHA,
                       "recomputed hash drifted from the asset — bundle may be corrupt")
        XCTAssertTrue(TajweedText.verifyChecksum())
    }

    func testRunsReconstructVerifiedRasm() {
        // The coloured overlay must line up with the verified `ar` for a sample of
        // ayahs: concatenated run text should share the same consonantal skeleton.
        for (s, a) in [(1, 1), (2, 255), (36, 1), (112, 1), (114, 6)] {
            guard let runs = TajweedText.runs(surah: s, ayah: a) else {
                return XCTFail("missing runs for \(s):\(a)")
            }
            XCTAssertFalse(runs.isEmpty)
            let plain = runs.map(\.text).joined()
            XCTAssertEqual(skeleton(plain), skeleton(QuranText.ayah(surah: s, ayah: a)?.ar ?? "-"),
                           "overlay rasm mismatch at \(s):\(a)")
        }
    }

    func testEveryRuleCodeMapsToAFamily() {
        // Sanity: all rules resolve to one of the eight legend families.
        for rule in TajweedRule.allCases {
            XCTAssertTrue(TajweedRule.Family.allCases.contains(rule.family))
        }
    }

    /// Coarse consonantal skeleton — mirrors the build tool closely enough for a
    /// per-ayah alignment check (drops harakat/hamza, unifies alef variants).
    private func skeleton(_ t: String) -> String {
        var out: [Character] = []
        for scalar in t.unicodeScalars {
            let ch = Character(scalar)
            let v = scalar.value
            if "ءٱٔ ٕ".contains(ch) { continue }
            if "اٱآأإىٲٳٮ".contains(ch) || v == 0x0670 {
                if out.last != "ا" { out.append("ا") }
                continue
            }
            if ch == "ؤ" { out.append("و"); continue }
            if ch == "ئ" { if out.last != "ا" { out.append("ا") }; continue }
            // combining marks, tatweel, small annotation signs, zero-width, spaces
            if (0x0610...0x061A).contains(v) || (0x064B...0x065F).contains(v)
                || (0x06D6...0x06ED).contains(v) || v == 0x0640 || v == 0x0670
                || (0x200C...0x200F).contains(v) || v == 0xFEFF || ch == " " {
                continue
            }
            out.append(ch)
        }
        return String(out)
    }
}
