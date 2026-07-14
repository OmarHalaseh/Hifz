import Foundation

/// Bridges the fine-grained ayah-atomic ḥifẓ program (`HifzAyah`) with the coarse
/// surah/page/juz tracking (`MemorizationProgress`) so every screen shows one
/// unified picture of progress.
///
/// "Memorized" is a **union**: a track unit counts as memorized when *all* of its
/// ayahs have been memorized in the program **or** it was marked memorized
/// manually; a unit with some — but not all — memorized ayahs (or a manual
/// "learning" mark) reads as `.learning`. This lets the Sabaq/Sabqi/Manzil program
/// and the older manual marking both feed the same displayed status without a
/// schema change — coverage is derived on read, never stored.
enum MemorizationCoverage {

    static func ayahKey(surah: Int, ayah: Int) -> String { "\(surah):\(ayah)" }

    /// The ayah keys (`"surah:ayah"`) that make up a track unit.
    static func ayahKeys(in unit: TrackUnit) -> [String] {
        switch unit.granularity {
        case .surah:
            return QuranText.ayahs(surah: unit.surahNumber).map { ayahKey(surah: unit.surahNumber, ayah: $0.n) }
        case .page:
            return keysByPage[unit.pageNumber] ?? []
        case .juz:
            return keysByJuz[unit.juzNumber] ?? []
        case .ayahRange:
            guard unit.ayahTo >= unit.ayahFrom else { return [] }
            return (unit.ayahFrom...unit.ayahTo).map { ayahKey(surah: unit.surahNumber, ayah: $0) }
        case .halfPage, .quarterPage, .line:
            // Page-portion units cover a line range; their ayahs are whatever the
            // printed lines in that range carry (same source as `ReaderCoverage`).
            return MushafLayout.lines(onPage: unit.pageNumber)
                .filter { unit.lineFrom <= $0.l && $0.l <= unit.lineTo }
                .flatMap { $0.segments.map { ayahKey(surah: $0.surah, ayah: $0.ayah) } }
        }
    }

    /// How many ayahs a unit has, and how many of them are memorized in the program.
    static func counts(for unit: TrackUnit, memorizedKeys: Set<String>) -> (total: Int, memorized: Int) {
        let keys = ayahKeys(in: unit)
        let memorized = keys.reduce(0) { $0 + (memorizedKeys.contains($1) ? 1 : 0) }
        return (keys.count, memorized)
    }

    /// The unit's effective status, unioning program coverage with any manual mark.
    static func status(
        for unit: TrackUnit,
        memorizedKeys: Set<String>,
        stored: MemorizationStatus?
    ) -> MemorizationStatus {
        let c = counts(for: unit, memorizedKeys: memorizedKeys)
        if stored == .memorized || (c.total > 0 && c.memorized == c.total) { return .memorized }
        if stored == .learning || c.memorized > 0 { return .learning }
        return .notStarted
    }

    /// Effective status for every unit of a granularity, keyed by unit key — the
    /// shared input for the Dashboard counts, the Statistics pie, and the Surah list.
    static func statusByUnitKey(
        units: [TrackUnit],
        memorizedKeys: Set<String>,
        stored: [String: MemorizationStatus]
    ) -> [String: MemorizationStatus] {
        var out: [String: MemorizationStatus] = [:]
        out.reserveCapacity(units.count)
        for unit in units {
            out[unit.key] = status(for: unit, memorizedKeys: memorizedKeys, stored: stored[unit.key])
        }
        return out
    }

    /// Aggregate memorized / learning / not-started counts across a granularity.
    static func statusCounts(
        units: [TrackUnit],
        memorizedKeys: Set<String>,
        stored: [String: MemorizationStatus]
    ) -> (memorized: Int, learning: Int, notStarted: Int) {
        var memorized = 0, learning = 0
        for unit in units {
            switch status(for: unit, memorizedKeys: memorizedKeys, stored: stored[unit.key]) {
            case .memorized: memorized += 1
            case .learning:  learning += 1
            case .notStarted: break
            }
        }
        return (memorized, learning, max(0, units.count - memorized - learning))
    }

    /// The set of memorized ayah keys from the program's `HifzAyah` rows.
    static func memorizedKeys(from ayahs: [HifzAyah]) -> Set<String> {
        Set(ayahs.filter(\.isMemorized).map(\.key))
    }

    /// Every ayah key physically printed on a mushaf page, whether memorized or not
    /// — the full page membership the page scheduler uses to judge completeness.
    static func pageAyahKeys(_ page: Int) -> [String] { keysByPage[page] ?? [] }

    /// Stored manual statuses keyed by unit key, scoped to one granularity.
    static func storedStatus(from progress: [MemorizationProgress], granularity: Granularity) -> [String: MemorizationStatus] {
        Dictionary(
            progress.filter { $0.granularity == granularity }.map { ($0.unitKey, $0.status) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    // MARK: - Memoized ayah indexes (built once from the reference text)

    private static let keysByPage: [Int: [String]] = index(by: \.page)
    private static let keysByJuz: [Int: [String]] = index(by: \.juz)

    private static func index(by field: KeyPath<QuranAyah, Int>) -> [Int: [String]] {
        var dict: [Int: [String]] = [:]
        for (surah, ayah) in QuranText.orderedAtoms {
            dict[ayah[keyPath: field], default: []].append(ayahKey(surah: surah, ayah: ayah.n))
        }
        return dict
    }
}
