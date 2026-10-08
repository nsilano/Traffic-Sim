import AVFoundation

/// Plays the chiptune sound effects (Sounds/*.wav, made by ios/make-sounds.py).
/// Uses the ambient audio session, so the silent switch mutes it and music keeps playing.
final class SoundPlayer {
    static let names = ["tap", "go", "stop", "crash", "siren", "clear", "held", "combo", "wave", "streak", "win", "lose"]

    // A few players per sound, so quick repeats (two lights switched at once) overlap
    // instead of cutting each other off.
    private var players: [String: [AVAudioPlayer]] = [:]
    private var next: [String: Int] = [:]

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        for name in Self.names {
            guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else { continue }
            let pool = (0..<3).compactMap { _ in try? AVAudioPlayer(contentsOf: url) }
            for player in pool { player.prepareToPlay() }
            players[name] = pool
        }
    }

    func play(_ name: String) {
        guard let pool = players[name], !pool.isEmpty else { return }
        let i = next[name, default: 0]
        next[name] = (i + 1) % pool.count
        let player = pool[i]
        player.currentTime = 0
        player.play()
    }
}
