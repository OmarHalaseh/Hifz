import Foundation

/// Pure decision logic for the Sabaq / Sabqi / Manzil ḥifẓ program. No SwiftData
/// or UI here so it can be unit-tested directly; `HifzProgramManager` applies the
/// results to the store.
///
/// Design intent (from the memorization strategy):
///  1. SABAQ  — a small new portion (3–10 lines of the Madani mushaf), sized down
///     after weak days. A portion counts as memorized only on one flawless recall.
///  2. SABQI  — everything memorized in the last 7 days, recited *before* any new
///     Sabaq. No new Sabaq until today's Sabqi is cleared.
///  3. MANZIL — a fixed rotation over all older material so the whole ḥifẓ is seen
///     every ~7–30 days depending on volume.
enum HifzProgram {

    // MARK: - Portion sizing (Sabaq)

    static let linesPerPage = 15.0
    static var ayahsPerPage: Double { Double(QuranData.totalAyahs) / Double(QuranData.totalPages) }

    /// A "lines" portion (3–10) expressed as a whole number of ayahs. We ship
    /// ayah→page but not ayah→line (deferred P4), so this is a faithful average,
    /// not a glyph-exact line count.
    static func ayahCount(forLines lines: Int) -> Int {
        max(1, Int((Double(lines) / linesPerPage * ayahsPerPage).rounded()))
    }

    /// Portion size in lines, clamped to 3…10, nudged by recent accuracy (0…1):
    /// shrink after weak days, grow after strong ones.
    static func portionLines(baseLines: Int = 5, recentAccuracy: Double) -> Int {
        let adjusted: Int
        switch recentAccuracy {
        case ..<0.6:  adjusted = baseLines - 2
        case ..<0.85: adjusted = baseLines
        default:      adjusted = baseLines + 2
        }
        return min(10, max(3, adjusted))
    }

    /// Recall accuracy from recent session outcomes (1.0 == flawless, no data == 1.0).
    static func recentAccuracy(reviews: Int, mistakes: Int) -> Double {
        guard reviews > 0 else { return 1 }
        return max(0, 1 - Double(mistakes) / Double(reviews))
    }

    /// The next unmemorized ayahs in mushaf order, for a fresh Sabaq portion.
    static func nextSabaqAtoms(
        orderedAtoms: [(surah: Int, ayah: Int, page: Int, juz: Int)],
        memorizedOrInProgressKeys: Set<String>,
        count: Int
    ) -> [(surah: Int, ayah: Int, page: Int, juz: Int)] {
        var out: [(surah: Int, ayah: Int, page: Int, juz: Int)] = []
        for atom in orderedAtoms {
            if out.count >= count { break }
            let key = HifzAyah.makeKey(surah: atom.surah, ayah: atom.ayah)
            if !memorizedOrInProgressKeys.contains(key) {
                out.append(atom)
            }
        }
        return out
    }

    // MARK: - Sabqi (recent revision, blocking)

    /// Ayahs memorized within the last `days` days, in mushaf order.
    static func sabqiQueue(
        _ ayahs: [HifzAyah],
        now: Date = .now,
        days: Int = 7,
        calendar: Calendar = .current
    ) -> [HifzAyah] {
        let start = calendar.startOfDay(for: now)
        guard let cutoff = calendar.date(byAdding: .day, value: -days, to: start) else { return [] }
        return ayahs
            .filter { ($0.memorizedAt ?? .distantPast) >= cutoff }
            .sorted(by: mushafOrder)
    }

    /// New Sabaq is only allowed once today's Sabqi is empty or has been cleared.
    static func isSabaqUnlocked(
        sabqiCount: Int,
        sabqiClearedOn: Date?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        if sabqiCount == 0 { return true }
        guard let cleared = sabqiClearedOn else { return false }
        return calendar.isDate(cleared, inSameDayAs: now)
    }

    // MARK: - Manzil (long-term rotation)

    /// Days for one full pass over all memorized material, scaled by volume.
    static func recommendedCycleDays(memorizedPages: Int) -> Int {
        switch memorizedPages {
        case ..<30:  return 7
        case ..<120: return 15
        default:     return 30
        }
    }

    /// Pages to review per day so the whole ḥifẓ is seen within the recommended cycle.
    static func pagesPerDay(memorizedPages: Int) -> Int {
        guard memorizedPages > 0 else { return 0 }
        let cycle = recommendedCycleDays(memorizedPages: memorizedPages)
        return max(1, Int((Double(memorizedPages) / Double(cycle)).rounded(.up)))
    }

    /// Today's Manzil slice: `pagesPerDay` pages starting at the rotation cursor,
    /// wrapping around the sorted list of memorized pages. Sabqi (last 7 days) is
    /// excluded — that material is handled by Sabqi, not the long-term cycle.
    static func manzilQueue(
        _ ayahs: [HifzAyah],
        cursor: Int,
        now: Date = .now,
        sabqiDays: Int = 7,
        calendar: Calendar = .current
    ) -> [HifzAyah] {
        let start = calendar.startOfDay(for: now)
        let cutoff = calendar.date(byAdding: .day, value: -sabqiDays, to: start) ?? start
        let longTerm = ayahs.filter { a in
            guard let m = a.memorizedAt else { return false }
            return m < cutoff
        }
        let pages = Set(longTerm.map(\.page)).sorted()
        guard !pages.isEmpty else { return [] }

        let perDay = pagesPerDay(memorizedPages: pages.count)
        let startIndex = ((cursor % pages.count) + pages.count) % pages.count
        let rotated = Array(pages[startIndex...] + pages[..<startIndex])
        let todaysPages = Set(rotated.prefix(perDay))

        return longTerm
            .filter { todaysPages.contains($0.page) }
            .sorted(by: mushafOrder)
    }

    /// Advance the rotation cursor by the pages covered today.
    static func advanceCursor(cursor: Int, memorizedPageCount: Int) -> Int {
        guard memorizedPageCount > 0 else { return 0 }
        let perDay = pagesPerDay(memorizedPages: memorizedPageCount)
        return (cursor + perDay) % memorizedPageCount
    }

    // MARK: - Weak links

    /// Memorized ayahs missed repeatedly, worst first — targets for extra reps.
    static func weakLinks(_ ayahs: [HifzAyah], threshold: Int = 3) -> [HifzAyah] {
        ayahs
            .filter { $0.isMemorized && $0.mistakeCount >= threshold }
            .sorted { $0.mistakeCount > $1.mistakeCount }
    }

    // MARK: - Ordering

    static func mushafOrder(_ a: HifzAyah, _ b: HifzAyah) -> Bool {
        (a.surah, a.ayah) < (b.surah, b.ayah)
    }
}
