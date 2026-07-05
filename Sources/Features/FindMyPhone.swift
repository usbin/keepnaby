import AVFoundation
import UIKit

final class FindMyPhone {
    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var vibrationTimer: Timer?
    private var savedVolume: Float?

    func play() {
        // 진동은 소리 성공/실패와 무관하게 항상 병행 (음량 0에서 소리가 안 나도 위치 파악용)
        startVibration()

        // 비공개 API로 시스템(미디어) 음량을 최대로 올려 음량 0에서도 소리가 나게 함.
        // 실패해도 진동/일반재생으로 폴백되도록 SystemVolume 내부에서 전부 방어 처리.
        savedVolume = SystemVolume.current()
        SystemVolume.set(1.0)

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
        } catch {
            // 오디오 세션 활성화 실패 — 진동은 이미 startVibration()으로 동작 중.
        }

        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
            self?.stop()
        }
    }

    private func startVibration() {
        vibrationTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { _ in
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
        vibrationTimer?.fire()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        vibrationTimer?.invalidate()
        vibrationTimer = nil
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        // 강제로 올렸던 시스템 음량을 원래 값으로 복구
        if let v = savedVolume {
            SystemVolume.set(v)
            savedVolume = nil
        }
    }
}

/// 비공개 `AVSystemController` 를 통한 시스템(미디어) 음량 제어.
/// App Store 심사가 없는 **사이드로드 개인 앱 전용**. 비공개 API 이므로 iOS 업데이트로
/// 언제든 깨질 수 있어 모든 경로를 방어적으로 처리하고, 실패 시 조용히 무시한다.
enum SystemVolume {
    private static let category = "Audio" as NSString  // "Audio" = 미디어 볼륨

    /// 현재 시스템 음량 (공개 API 로 충분)
    static func current() -> Float {
        return AVAudioSession.sharedInstance().outputVolume
    }

    /// 시스템 음량을 지정 값(0.0~1.0)으로 강제 설정. 실패 시 조용히 무시.
    static func set(_ value: Float) {
        guard let controller = sharedController() else { return }
        let sel = NSSelectorFromString("setVolumeTo:forCategory:")
        guard let method = class_getInstanceMethod(type(of: controller), sel) else { return }
        typealias Fn = @convention(c) (NSObject, Selector, Float, NSString) -> Bool
        let fn = unsafeBitCast(method_getImplementation(method), to: Fn.self)
        _ = fn(controller, sel, value, category)
    }

    private static func sharedController() -> NSObject? {
        guard let cls = NSClassFromString("AVSystemController") else { return nil }
        let sel = NSSelectorFromString("sharedAVSystemController")
        guard let method = class_getClassMethod(cls, sel) else { return nil }
        typealias Fn = @convention(c) (AnyClass, Selector) -> NSObject?
        let fn = unsafeBitCast(method_getImplementation(method), to: Fn.self)
        return fn(cls, sel)
    }
}
