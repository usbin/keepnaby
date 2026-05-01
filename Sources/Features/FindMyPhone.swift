import AVFoundation
import UIKit

final class FindMyPhone {
    private var player: AVAudioPlayer?
    private var timer: Timer?

    func play() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .default,
                options: [.duckOthers]
            )
            try AVAudioSession.sharedInstance().setActive(true)

            guard let soundURL = Bundle.main.url(forResource: "alarm", withExtension: "wav") else {
                throw NSError(domain: "FindMyPhone", code: -1)
            }
            let player = try AVAudioPlayer(contentsOf: soundURL)
            player.numberOfLoops = -1
            player.volume = 1.0
            player.prepareToPlay()
            player.play()
            self.player = player

            timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
                self?.stop()
            }
        } catch {
            // 안전장치: AVAudioSession 활성화 자체가 실패한 극단적인 상황에서만 진동
            for i in 0..<10 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.8) {
                    AudioServicesPlayAlertSound(SystemSoundID(1005))
                }
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
