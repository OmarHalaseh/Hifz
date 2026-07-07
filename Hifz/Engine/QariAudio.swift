import AVFoundation

/// Plays per-ayah qari recitation (default: Mishary Alafasy, everyayah.com).
/// Streaming; degrades silently if offline — the method still works from the page.
@MainActor
final class QariAudio: ObservableObject {
    static let shared = QariAudio()

    @Published private(set) var playingKey: String?

    private var player: AVPlayer?

    /// everyayah.com file naming: SSSAAA.mp3 (zero-padded surah + ayah).
    private func url(surah: Int, ayah: Int) -> URL? {
        let name = String(format: "%03d%03d", surah, ayah)
        return URL(string: "https://everyayah.com/data/Alafasy_128kbps/\(name).mp3")
    }

    func play(surah: Int, ayah: Int) {
        guard let url = url(surah: surah, ayah: ayah) else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)
        playingKey = HifzAyah.makeKey(surah: surah, ayah: ayah)
        player?.play()
    }

    func stop() {
        player?.pause()
        player = nil
        playingKey = nil
    }
}
