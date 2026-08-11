import Foundation
import SwiftData

/// The three stages of the classical ḥifẓ cycle. An ayah moves
/// `sabaq → sabqi → manzil` as it matures.
enum HifzPhase: String, Codable, CaseIterable, Identifiable {
    case sabaq   // brand-new lesson being learned
    case sabqi   // memorized in the last 7 days (recent revision)
    case manzil  // long-term, on the rotation cycle

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sabaq:  return "Sabaq"
        case .sabqi:  return "Sabqi"
        case .manzil: return "Manzil"
        }
    }

    var subtitle: String {
        switch self {
        case .sabaq:  return "New lesson"
        case .sabqi:  return "Recent revision"
        case .manzil: return "Long-term revision"
        }
    }

    var systemImage: String {
        switch self {
        case .sabaq:  return "sparkles"
        case .sabqi:  return "clock.arrow.circlepath"
        case .manzil: return "arrow.triangle.2.circlepath"
        }
    }
}

/// One ayah as an atomic ḥifẓ unit. This is the ayah-atomic model the
/// Sabaq/Sabqi/Manzil program is built on (page/juz are derived via `page`/`juz`).
/// It lives alongside the existing `MemorizationProgress` rather than replacing it.
@Model
final class HifzAyah {
    /// Stable identity, `"surah:ayah"`, e.g. `"2:255"`.
    @Attribute(.unique) var key: String

    var surah: Int
    var ayah: Int
    var page: Int
    var juz: Int

    var phase: HifzPhase

    /// Set exactly once, on the first flawless recitation from memory. Never set
    /// speculatively — this is the "quality over speed" gate.
    var memorizedAt: Date?
    var lastReviewedAt: Date?

    /// Lifetime count of mistakes at this ayah — drives "weak link" targeting.
    var mistakeCount: Int

    // SM-2 state used for Manzil scheduling (reuses `SpacedRepetition`).
    var easeFactor: Double
    var intervalDays: Int
    var repetitions: Int
    var dueDate: Date?

    init(surah: Int, ayah: Int, page: Int, juz: Int, phase: HifzPhase = .sabaq) {
        self.key = HifzAyah.makeKey(surah: surah, ayah: ayah)
        self.surah = surah
        self.ayah = ayah
        self.page = page
        self.juz = juz
        self.phase = phase
        self.memorizedAt = nil
        self.lastReviewedAt = nil
        self.mistakeCount = 0
        self.easeFactor = 2.5
        self.intervalDays = 0
        self.repetitions = 0
        self.dueDate = nil
    }

    static func makeKey(surah: Int, ayah: Int) -> String { "\(surah):\(ayah)" }

    var isMemorized: Bool { memorizedAt != nil }
}

/// One ayah-level mistake, logged during a session. Repeated mistakes on the same
/// ayah accumulate into `HifzAyah.mistakeCount` and surface as a "weak link".
@Model
final class MistakeLog {
    var date: Date
    var ayahKey: String
    /// "slip" (minor), "stuck" (blanked), or "tajweed".
    var kind: String

    init(date: Date = .now, ayahKey: String, kind: String) {
        self.date = date
        self.ayahKey = ayahKey
        self.kind = kind
    }
}

/// Single-row orchestration state for the daily ḥifẓ program: whether today's
/// Sabqi has been cleared, and the currently assigned Sabaq portion.
///
/// Manzil keeps no *live* state here — `HifzPageScheduler` derives each page's due
/// date from its ayahs' spaced-repetition state, so there is nothing to point at.
@Model
final class HifzProgramState {
    /// Dead weight, kept deliberately: the rotation cursor of the old cursor-based
    /// Manzil cycle, which `HifzPageScheduler` replaced. Nothing reads or writes it.
    ///
    /// It cannot simply be deleted. Every `SchemaVn` in `HifzSchema` lists the
    /// *live* model classes rather than frozen per-version copies, so all versions
    /// hash to the same checksum. That goes unnoticed while changes are additive
    /// and CoreData needs no real migration — but dropping an attribute forces one,
    /// the migration plan gets evaluated, and SwiftData aborts with "Duplicate
    /// version checksums detected". Removing this field therefore has to wait until
    /// each versioned schema owns frozen copies of its models.
    var manzilCursor: Int = 0

    /// Start-of-day on which today's Sabqi was fully recited. Gates new Sabaq.
    var sabqiClearedOn: Date?

    /// Start-of-day the current Sabaq portion was assigned.
    var sabaqAssignedOn: Date?
    /// The ayah keys in the current Sabaq portion.
    var sabaqKeys: [String]
    /// The subset already confirmed flawless-from-memory today.
    var sabaqConfirmedKeys: [String]

    init(
        sabqiClearedOn: Date? = nil,
        sabaqAssignedOn: Date? = nil,
        sabaqKeys: [String] = [],
        sabaqConfirmedKeys: [String] = []
    ) {
        self.sabqiClearedOn = sabqiClearedOn
        self.sabaqAssignedOn = sabaqAssignedOn
        self.sabaqKeys = sabaqKeys
        self.sabaqConfirmedKeys = sabaqConfirmedKeys
    }

    /// Fetches the single state row, creating it on first use.
    static func current(in context: ModelContext) -> HifzProgramState {
        if let existing = try? context.fetch(FetchDescriptor<HifzProgramState>()).first {
            return existing
        }
        let state = HifzProgramState()
        context.insert(state)
        return state
    }
}
