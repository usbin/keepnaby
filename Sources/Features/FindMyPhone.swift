import AVFoundation
import UIKit

final class FindMyPhone {
    private var player: AVAudioPlayer?

    func play() {
        // Use system sound for maximum volume even in silent mode
        AudioServicesPlayAlertSound(SystemSoundID(1005))

        // Also play with AVAudioPlayer for longer duration
        guard let url = Bundle.main.url(forResource: "findme", withExtension: "caf")
                ?? createBeepURL() else { return }

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, options: .duckOthers)
            try AVAudioSession.sharedInstance().setActive(true)
            player = try AVAudioPlayer(contentsOf: url)
            player?.numberOfLoops = 5
            player?.volume = 1.0
            player?.play()
        } catch {
            // Fallback: system alert sound
            for i in 0..<5 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.8) {
                    AudioServicesPlayAlertSound(SystemSoundID(1005))
                }
            }
        }
    }

    func stop() {
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    private func createBeepURL() -> URL? {
        // No bundled sound file — just use system sounds
        nil
    }
}
