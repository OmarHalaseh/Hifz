import Foundation
import SwiftData

/// A complete snapshot of everything the app stores, as one JSON file.
///
/// All Hifz data lives only on this device — there is no account and no cloud
/// sync — so an export the user can keep in Files (or hand on to Drive, Dropbox,
/// a Mac) is the entire backup story. Losing the phone must not mean losing years
/// of ḥifẓ.
///
/// The format is deliberately plain and forgiving: field names mirror the models,
/// enums travel as their raw values, and anything with a sensible default is
/// optional — so an archive written by one build still restores into a later one
/// whose schema has grown.
struct BackupArchive: Codable {

    /// Bumped only when the layout changes in a way older builds cannot read.
    static let currentFormat = 1

    var format: Int = BackupArchive.currentFormat
    var appVersion: String = ""
    var exportedAt: Date = .now

    var settings: SettingsRow?
    var programState: ProgramStateRow?
    var progress: [ProgressRow] = []
    var ayahs: [AyahRow] = []
    var reviews: [ReviewRow] = []
    var mistakes: [MistakeRow] = []

    init() {}

    private enum CodingKeys: String, CodingKey {
        case format, appVersion, exportedAt, settings, programState, progress, ayahs, reviews, mistakes
    }

    /// Decoded by hand rather than by the synthesized initializer, which ignores
    /// property defaults and so would reject any archive missing a key an older
    /// build didn't write. Every section is optional — except `format`, which every
    /// Hifz export carries and which is therefore what tells a backup apart from
    /// some other JSON file. Without that check, arbitrary JSON would decode to an
    /// *empty* archive and a restore would happily wipe the store with it.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let format = try c.decodeIfPresent(Int.self, forKey: .format) else {
            throw BackupError.unreadable
        }
        self.format = format
        appVersion = try c.decodeIfPresent(String.self, forKey: .appVersion) ?? ""
        exportedAt = try c.decodeIfPresent(Date.self, forKey: .exportedAt) ?? .now
        settings = try c.decodeIfPresent(SettingsRow.self, forKey: .settings)
        programState = try c.decodeIfPresent(ProgramStateRow.self, forKey: .programState)
        progress = try c.decodeIfPresent([ProgressRow].self, forKey: .progress) ?? []
        ayahs = try c.decodeIfPresent([AyahRow].self, forKey: .ayahs) ?? []
        reviews = try c.decodeIfPresent([ReviewRow].self, forKey: .reviews) ?? []
        mistakes = try c.decodeIfPresent([MistakeRow].self, forKey: .mistakes) ?? []
    }

    // MARK: - Rows

    struct SettingsRow: Codable {
        var granularity: String?
        var revisionMode: String?
        var remindersEnabled: Bool?
        var reminderHour: Int?
        var reminderMinute: Int?
        var dailyGoal: Int?
        var dailyNewAyahs: Int?
        var sabaqUnit: String?
        var hasSetGoal: Bool?
        var memorizeReminderEnabled: Bool?
        var memorizeReminderHour: Int?
        var memorizeReminderMinute: Int?
    }

    struct ProgramStateRow: Codable {
        // Archives from earlier builds also carry `manzilCursor`, an attribute
        // dropped in `SchemaV5`. Unknown keys are ignored on decode, so those files
        // still restore.
        var sabqiClearedOn: Date?
        var sabaqAssignedOn: Date?
        var sabaqKeys: [String]?
        var sabaqConfirmedKeys: [String]?
    }

    struct ProgressRow: Codable {
        var unitKey: String
        var granularity: String?
        var surahNumber: Int?
        var pageNumber: Int?
        var juzNumber: Int?
        var ayahFrom: Int?
        var ayahTo: Int?
        var lineFrom: Int?
        var lineTo: Int?
        var status: String?
        var strength: Double?
        var easeFactor: Double?
        var intervalDays: Int?
        var repetitions: Int?
        var dueDate: Date?
        var lastReviewedAt: Date?
        var createdAt: Date?
        var memorizedAt: Date?
    }

    struct AyahRow: Codable {
        var surah: Int
        var ayah: Int
        var page: Int?
        var juz: Int?
        var phase: String?
        var memorizedAt: Date?
        var lastReviewedAt: Date?
        var mistakeCount: Int?
        var easeFactor: Double?
        var intervalDays: Int?
        var repetitions: Int?
        var dueDate: Date?
    }

    struct ReviewRow: Codable {
        var date: Date
        var unitKey: String
        var rating: Int?
        var intervalAfter: Int?
    }

    struct MistakeRow: Codable {
        var date: Date
        var ayahKey: String
        var kind: String?
    }

    // MARK: - Coding

    static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    func encoded() throws -> Data { try Self.encoder.encode(self) }

    static func decoded(from data: Data) throws -> BackupArchive {
        let archive: BackupArchive
        do {
            archive = try decoder.decode(BackupArchive.self, from: data)
        } catch let error as BackupError {
            throw error
        } catch {
            // Malformed JSON, wrong shape, unparseable dates — all one thing to
            // the user: this file isn't a usable backup.
            throw BackupError.unreadable
        }
        guard archive.format <= currentFormat else { throw BackupError.tooNew(archive.format) }
        return archive
    }

    /// Suggested filename, dated so successive exports sit side by side.
    var suggestedFilename: String {
        let stamp = ISO8601DateFormatter.backupStamp.string(from: exportedAt)
        return "Hifz-Backup-\(stamp)"
    }

    /// One-line "what's in here", shown before a restore overwrites anything.
    var summary: String {
        let parts = [
            "\(ayahs.count) ayah\(ayahs.count == 1 ? "" : "s")",
            "\(progress.count) tracked unit\(progress.count == 1 ? "" : "s")",
            "\(reviews.count) review\(reviews.count == 1 ? "" : "s")",
        ]
        return parts.joined(separator: " · ")
    }

    // MARK: - Capture

    /// Reads the whole store into an archive.
    static func capture(from context: ModelContext, appVersion: String = Self.bundleVersion) throws -> BackupArchive {
        var archive = BackupArchive()
        archive.appVersion = appVersion

        if let s = try context.fetch(FetchDescriptor<AppSettings>()).first {
            archive.settings = SettingsRow(
                granularity: s.granularity.rawValue,
                revisionMode: s.revisionMode.rawValue,
                remindersEnabled: s.remindersEnabled,
                reminderHour: s.reminderHour,
                reminderMinute: s.reminderMinute,
                dailyGoal: s.dailyGoal,
                dailyNewAyahs: s.dailyNewAyahs,
                sabaqUnit: s.sabaqUnit.rawValue,
                hasSetGoal: s.hasSetGoal,
                memorizeReminderEnabled: s.memorizeReminderEnabled,
                memorizeReminderHour: s.memorizeReminderHour,
                memorizeReminderMinute: s.memorizeReminderMinute
            )
        }

        if let p = try context.fetch(FetchDescriptor<HifzProgramState>()).first {
            archive.programState = ProgramStateRow(
                sabqiClearedOn: p.sabqiClearedOn,
                sabaqAssignedOn: p.sabaqAssignedOn,
                sabaqKeys: p.sabaqKeys,
                sabaqConfirmedKeys: p.sabaqConfirmedKeys
            )
        }

        // Built with explicit locals rather than one large literal per row: the
        // many-optional initializers are slow for the type checker inlined.
        for p in try context.fetch(FetchDescriptor<MemorizationProgress>()) {
            var row = ProgressRow(unitKey: p.unitKey)
            row.granularity = p.granularity.rawValue
            row.surahNumber = p.surahNumber
            row.pageNumber = p.pageNumber
            row.juzNumber = p.juzNumber
            row.ayahFrom = p.ayahFrom
            row.ayahTo = p.ayahTo
            row.lineFrom = p.lineFrom
            row.lineTo = p.lineTo
            row.status = p.status.rawValue
            row.strength = p.strength
            row.easeFactor = p.easeFactor
            row.intervalDays = p.intervalDays
            row.repetitions = p.repetitions
            row.dueDate = p.dueDate
            row.lastReviewedAt = p.lastReviewedAt
            row.createdAt = p.createdAt
            row.memorizedAt = p.memorizedAt
            archive.progress.append(row)
        }

        for a in try context.fetch(FetchDescriptor<HifzAyah>()) {
            var row = AyahRow(surah: a.surah, ayah: a.ayah)
            row.page = a.page
            row.juz = a.juz
            row.phase = a.phase.rawValue
            row.memorizedAt = a.memorizedAt
            row.lastReviewedAt = a.lastReviewedAt
            row.mistakeCount = a.mistakeCount
            row.easeFactor = a.easeFactor
            row.intervalDays = a.intervalDays
            row.repetitions = a.repetitions
            row.dueDate = a.dueDate
            archive.ayahs.append(row)
        }

        for r in try context.fetch(FetchDescriptor<ReviewLog>()) {
            archive.reviews.append(ReviewRow(date: r.date, unitKey: r.unitKey,
                                             rating: r.rating.rawValue,
                                             intervalAfter: r.intervalAfter))
        }

        for m in try context.fetch(FetchDescriptor<MistakeLog>()) {
            archive.mistakes.append(MistakeRow(date: m.date, ayahKey: m.ayahKey, kind: m.kind))
        }

        return archive
    }

    // MARK: - Restore

    /// Replaces the entire store with this archive.
    ///
    /// A restore is a restore, not a merge: the store is emptied first. Merging
    /// would silently duplicate every review and mistake (they have no unique key)
    /// and leave two conflicting schedules for the same ayah.
    func restore(into context: ModelContext) throws {
        try context.delete(model: ReviewLog.self)
        try context.delete(model: MistakeLog.self)
        try context.delete(model: HifzAyah.self)
        try context.delete(model: MemorizationProgress.self)
        try context.delete(model: HifzProgramState.self)
        try context.delete(model: AppSettings.self)

        if let s = settings {
            let row = AppSettings(
                granularity: Granularity(rawValue: s.granularity ?? "") ?? .surah,
                revisionMode: RevisionMode(rawValue: s.revisionMode ?? "") ?? .spacedRepetition,
                remindersEnabled: s.remindersEnabled ?? false,
                reminderHour: s.reminderHour ?? 20,
                reminderMinute: s.reminderMinute ?? 0,
                dailyGoal: s.dailyGoal ?? 5,
                dailyNewAyahs: s.dailyNewAyahs ?? 3,
                sabaqUnit: MushafUnitKind(rawValue: s.sabaqUnit ?? "") ?? .quarter,
                hasSetGoal: s.hasSetGoal ?? false,
                memorizeReminderEnabled: s.memorizeReminderEnabled ?? false,
                memorizeReminderHour: s.memorizeReminderHour ?? 7,
                memorizeReminderMinute: s.memorizeReminderMinute ?? 0
            )
            context.insert(row)
        }

        if let p = programState {
            context.insert(HifzProgramState(
                sabqiClearedOn: p.sabqiClearedOn,
                sabaqAssignedOn: p.sabaqAssignedOn,
                sabaqKeys: p.sabaqKeys ?? [],
                sabaqConfirmedKeys: p.sabaqConfirmedKeys ?? []
            ))
        }

        for r in progress {
            let row = MemorizationProgress(
                unitKey: r.unitKey,
                granularity: Granularity(rawValue: r.granularity ?? "") ?? .surah,
                surahNumber: r.surahNumber ?? 0,
                pageNumber: r.pageNumber ?? 0,
                juzNumber: r.juzNumber ?? 0,
                ayahFrom: r.ayahFrom ?? 0,
                ayahTo: r.ayahTo ?? 0,
                lineFrom: r.lineFrom ?? 0,
                lineTo: r.lineTo ?? 0,
                status: MemorizationStatus(rawValue: r.status ?? "") ?? .notStarted
            )
            row.strength = r.strength ?? 0.5
            row.easeFactor = r.easeFactor ?? 2.5
            row.intervalDays = r.intervalDays ?? 0
            row.repetitions = r.repetitions ?? 0
            row.dueDate = r.dueDate
            row.lastReviewedAt = r.lastReviewedAt
            row.createdAt = r.createdAt ?? .now
            row.memorizedAt = r.memorizedAt
            context.insert(row)
        }

        for r in ayahs {
            let row = HifzAyah(
                surah: r.surah, ayah: r.ayah,
                page: r.page ?? 0, juz: r.juz ?? 0,
                phase: HifzPhase(rawValue: r.phase ?? "") ?? .sabaq
            )
            row.memorizedAt = r.memorizedAt
            row.lastReviewedAt = r.lastReviewedAt
            row.mistakeCount = r.mistakeCount ?? 0
            row.easeFactor = r.easeFactor ?? 2.5
            row.intervalDays = r.intervalDays ?? 0
            row.repetitions = r.repetitions ?? 0
            row.dueDate = r.dueDate
            context.insert(row)
        }

        for r in reviews {
            context.insert(ReviewLog(
                date: r.date, unitKey: r.unitKey,
                rating: ReviewRating(rawValue: r.rating ?? 2) ?? .good,
                intervalAfter: r.intervalAfter ?? 0
            ))
        }

        for r in mistakes {
            context.insert(MistakeLog(date: r.date, ayahKey: r.ayahKey, kind: r.kind ?? "slip"))
        }

        try context.save()
    }

    // MARK: - Helpers

    static var bundleVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}

/// Why a backup couldn't be read.
enum BackupError: LocalizedError {
    case tooNew(Int)
    case unreadable

    var errorDescription: String? {
        switch self {
        case .tooNew(let format):
            return "This backup was written by a newer version of Hifz (format \(format)). Update the app and try again."
        case .unreadable:
            return "That file isn't a Hifz backup, or it's damaged."
        }
    }
}

private extension ISO8601DateFormatter {
    /// `2026-08-10` — a date-only stamp for backup filenames.
    static let backupStamp: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()
}
