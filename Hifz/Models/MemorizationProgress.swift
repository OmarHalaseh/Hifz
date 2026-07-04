import Foundation
import SwiftData

/// Progress + spaced-repetition state for a single trackable unit
/// (a surah, a page, a juz, or an ayah range depending on granularity).
@Model
final class MemorizationProgress {
    /// Stable identity for the unit, e.g. "surah-2", "page-15", "juz-3", "ayah-2-1-5".
    @Attribute(.unique) var unitKey: String

    var granularity: Granularity

    // Identity fields — only the ones relevant to `granularity` are meaningful.
    var surahNumber: Int
    var pageNumber: Int
    var juzNumber: Int
    var ayahFrom: Int
    var ayahTo: Int

    var status: MemorizationStatus

    /// Self-rated recall strength, 0.0 (weak) … 1.0 (strong). Used by the by-strength mode.
    var strength: Double

    // SM-2 spaced-repetition state.
    var easeFactor: Double
    var intervalDays: Int
    var repetitions: Int
    var dueDate: Date?
    var lastReviewedAt: Date?

    var createdAt: Date
    var memorizedAt: Date?

    init(
        unitKey: String,
        granularity: Granularity,
        surahNumber: Int = 0,
        pageNumber: Int = 0,
        juzNumber: Int = 0,
        ayahFrom: Int = 0,
        ayahTo: Int = 0,
        status: MemorizationStatus = .notStarted
    ) {
        self.unitKey = unitKey
        self.granularity = granularity
        self.surahNumber = surahNumber
        self.pageNumber = pageNumber
        self.juzNumber = juzNumber
        self.ayahFrom = ayahFrom
        self.ayahTo = ayahTo
        self.status = status
        self.strength = 0.5
        self.easeFactor = 2.5
        self.intervalDays = 0
        self.repetitions = 0
        self.dueDate = nil
        self.lastReviewedAt = nil
        self.createdAt = .now
        self.memorizedAt = nil
    }

    // MARK: - Unit key builders

    static func surahKey(_ n: Int) -> String { "surah-\(n)" }
    static func pageKey(_ n: Int) -> String { "page-\(n)" }
    static func juzKey(_ n: Int) -> String { "juz-\(n)" }
    static func ayahKey(surah: Int, from: Int, to: Int) -> String { "ayah-\(surah)-\(from)-\(to)" }
}
