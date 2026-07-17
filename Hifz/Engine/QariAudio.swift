import AVFoundation

/// A selectable reciter. Raw value is the persisted id (stored via @AppStorage);
/// `folder` maps to the everyayah.com data directory that hosts the per-ayah files.
enum Qari: String, CaseIterable, Identifiable {
    case alafasy
    case husary
    case minshawy
    case maherAlMuaiqly
    case yasserAlDossary

    var id: String { rawValue }

    /// everyayah.com data folder name (see https://everyayah.com/data/).
    var folder: String {
        switch self {
        case .alafasy:         return "Alafasy_128kbps"
        case .husary:          return "Husary_128kbps"
        case .minshawy:        return "Minshawy_Murattal_128kbps"
        case .maherAlMuaiqly:  return "MaherAlMuaiqly128kbps"
        case .yasserAlDossary: return "Yasser_Ad-Dussary_128kbps"
        }
    }

    var displayName: String {
        switch self {
        case .alafasy:         return "Mishary Alafasy"
        case .husary:          return "Mahmoud Al-Husary"
        case .minshawy:        return "Mohamed Al-Minshawy"
        case .maherAlMuaiqly:  return "Maher Al-Muaiqly"
        case .yasserAlDossary: return "Yasser Al-Dossary"
        }
    }

    /// UserDefaults key shared with the Settings @AppStorage picker.
    static let storageKey = "selectedQari"

    /// The reciter the user picked in Settings, defaulting to Alafasy.
    static var selected: Qari {
        (UserDefaults.standard.string(forKey: storageKey)).flatMap(Qari.init(rawValue:)) ?? .alafasy
    }
}

/// Plays per-ayah qari recitation for the reciter chosen in Settings (default:
/// Mishary Alafasy, everyayah.com). Streaming; degrades silently if offline —
/// the method still works from the page.
@MainActor
final class QariAudio: ObservableObject {
    static let shared = QariAudio()

    /// True while any recitation (single ayah or a cumulative sequence) is playing.
    @Published private(set) var playingKey: String?

    private var player: AVQueuePlayer?
    private var endObserver: NSObjectProtocol?

    /// everyayah.com file naming: SSSAAA.mp3 (zero-padded surah + ayah).
    private func url(surah: Int, ayah: Int) -> URL? {
        let name = String(format: "%03d%03d", surah, ayah)
        return URL(string: "https://everyayah.com/data/\(Qari.selected.folder)/\(name).mp3")
    }

    func play(surah: Int, ayah: Int) {
        play(sequence: [(surah, ayah)])
    }

    /// Plays the given ayahs back-to-back (used by the cumulative Sabaq drill).
    /// `playingKey` tracks the first ayah for the duration and clears when the
    /// whole sequence finishes.
    func play(sequence: [(surah: Int, ayah: Int)]) {
        stop()
        let items = sequence.compactMap { url(surah: $0.surah, ayah: $0.ayah).map(AVPlayerItem.init) }
        guard let first = sequence.first, let last = items.last else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        let queue = AVQueuePlayer(items: items)
        player = queue
        playingKey = HifzAyah.makeKey(surah: first.surah, ayah: first.ayah)
        // Only the final item's end signals the sequence is done.
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: last, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.stop() }
        }
        queue.play()
    }

    func stop() {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        player?.pause()
        player = nil
        playingKey = nil
    }
}
