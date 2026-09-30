import SwiftUI

/// How finely the user tracks memorization. User-selectable in Settings.
enum Granularity: String, Codable, CaseIterable, Identifiable {
    case surah
    case page
    case halfPage
    case quarterPage
    case line
    case juz
    case ayahRange

    var id: String { rawValue }

    var label: String {
        switch self {
        case .surah: return "By Surah"
        case .page: return "By Page"
        case .halfPage: return "By Half Page"
        case .quarterPage: return "By Quarter Page"
        case .line: return "By Row (line)"
        case .juz: return "By Juz"
        case .ayahRange: return "By Ayah Range"
        }
    }

    var shortLabel: String {
        switch self {
        case .surah: return "Surah"
        case .page: return "Page"
        case .halfPage: return "½ Page"
        case .quarterPage: return "¼ Page"
        case .line: return "Row"
        case .juz: return "Juz"
        case .ayahRange: return "Ayah"
        }
    }

    var systemImage: String {
        switch self {
        case .surah: return "book.closed"
        case .page: return "doc.text"
        case .halfPage: return "doc.text.below.ecg"
        case .quarterPage: return "square.split.1x2"
        case .line: return "text.alignright"
        case .juz: return "square.stack"
        case .ayahRange: return "text.line.first.and.arrowtriangle.forward"
        }
    }

    /// How many ayahs one unit of the daily goal represents at this granularity,
    /// or `nil` to count the goal directly in ayahs (surah/ayah-range vary too
    /// much to be a meaningful daily unit). Page, its fractions, row, and juz are
    /// even shares of the whole — an estimate for setting a pace, unlike the
    /// forecast's memorized count, which is exact.
    var ayahsPerGoalUnit: Double? {
        let perPage = Double(QuranData.totalAyahs) / Double(QuranData.totalPages)
        switch self {
        case .page: return perPage
        case .halfPage: return perPage / 2
        case .quarterPage: return perPage / 4
        case .line: return perPage / MushafUnitKind.page.baseLines.asDouble  // one of 15 lines
        case .juz:  return Double(QuranData.totalAyahs) / Double(QuranData.totalJuz)
        case .surah, .ayahRange: return nil
        }
    }

    /// Singular/plural noun for the daily-goal unit ("page"/"pages", …).
    var goalUnitName: (one: String, many: String) {
        switch self {
        case .page: return ("page", "pages")
        case .halfPage: return ("half-page", "half-pages")
        case .quarterPage: return ("quarter-page", "quarter-pages")
        case .line: return ("row", "rows")
        case .juz:  return ("juz", "ajzāʼ")
        case .surah, .ayahRange: return ("ayah", "ayahs")
        }
    }
}

private extension Int {
    var asDouble: Double { Double(self) }
}

/// The lifecycle status of a memorization unit.
enum MemorizationStatus: String, Codable, CaseIterable, Identifiable {
    case notStarted
    case learning
    case memorized

    var id: String { rawValue }

    var label: String {
        switch self {
        case .notStarted: return "Not Started"
        case .learning: return "Learning"
        case .memorized: return "Memorized"
        }
    }

    var systemImage: String {
        switch self {
        case .notStarted: return "circle"
        case .learning: return "circle.lefthalf.filled"
        case .memorized: return "checkmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .notStarted: return .secondary
        case .learning: return .orange
        case .memorized: return .green
        }
    }
}

/// How the app decides what to revise. User-selectable; spaced repetition is default.
enum RevisionMode: String, Codable, CaseIterable, Identifiable {
    case spacedRepetition
    case lastReviewed
    case selfRated

    var id: String { rawValue }

    var label: String {
        switch self {
        case .spacedRepetition: return "Spaced Repetition"
        case .lastReviewed: return "Oldest Reviewed"
        case .selfRated: return "By Strength"
        }
    }

    var explanation: String {
        switch self {
        case .spacedRepetition:
            return "Reviews are scheduled automatically using intervals that grow as your recall improves (SM-2)."
        case .lastReviewed:
            return "Whatever you haven't reviewed for the longest time surfaces first."
        case .selfRated:
            return "The surahs you've rated weakest surface first."
        }
    }

    var systemImage: String {
        switch self {
        case .spacedRepetition: return "brain.head.profile"
        case .lastReviewed: return "clock.arrow.circlepath"
        case .selfRated: return "gauge.with.dots.needle.bottom.50percent"
        }
    }
}

/// The user's recall rating after reviewing an item — drives the SM-2 schedule.
enum ReviewRating: Int, Codable, CaseIterable, Identifiable {
    case again = 0   // forgot / blank
    case hard = 1    // recalled with difficulty
    case good = 2    // recalled correctly
    case easy = 3    // perfect, effortless

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .again: return "Again"
        case .hard: return "Hard"
        case .good: return "Good"
        case .easy: return "Easy"
        }
    }

    /// SM-2 quality value on the 0–5 scale.
    var quality: Int {
        switch self {
        case .again: return 1
        case .hard: return 3
        case .good: return 4
        case .easy: return 5
        }
    }

    var color: Color {
        switch self {
        case .again: return .red
        case .hard: return .orange
        case .good: return .green
        case .easy: return .blue
        }
    }

    var systemImage: String {
        switch self {
        case .again: return "arrow.counterclockwise"
        case .hard: return "tortoise"
        case .good: return "checkmark"
        case .easy: return "hare"
        }
    }
}
