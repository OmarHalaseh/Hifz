import SwiftUI

/// The typeface of the printed Madani mushaf: King Fahd Complex's
/// "KFGQPC HAFS Uthmanic Script", bundled under its free-redistribution licence
/// (unmodified). Every character of the bundled Tanzil text has a glyph in it.
///
/// It has tall ascenders and deep descenders for the stacked marks, so lines need
/// far less extra `lineSpacing` than the system Arabic font did.
extension Font {
    static let quranFontName = "KFGQPCHAFSUthmanicScript-Regula"

    /// Qur'anic text in the mushaf typeface. Falls back to the system font if the
    /// bundled file failed to register, so text never disappears.
    static func quran(size: CGFloat) -> Font {
        UIFont(name: quranFontName, size: size) != nil
            ? .custom(quranFontName, fixedSize: size)
            : .system(size: size)
    }
}

/// The end-of-ayah marker. The mushaf font draws Arabic-Indic digits as the
/// ornamental circle with the number inside on its own (one ornament even for
/// "٢٥٥"); prefixing U+06DD ۝ would add a second, empty ornament.
func ayahEndMarker(_ n: Int) -> String {
    arabicDigits(n)
}
