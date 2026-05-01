import Foundation
import UIKit

// MARK: - Action Types

enum ButtonActionType: String, Codable, CaseIterable {
    case none = "none"
    case findPhone = "find_phone"
    case showDate = "show_date"
    case showBattery = "show_battery"
    case showSteps = "show_steps"
    case musicPlayPause = "music_play_pause"
    case musicNext = "music_next"
    case musicPrevious = "music_previous"
    case recordLocation = "record_location"
    case randomDice = "random_dice"
    case iftttWebhook = "ifttt_webhook"
    case shortcut = "shortcut"
    case urlRequest = "url_request"

    var displayName: String {
        switch self {
        case .none: return "없음"
        case .findPhone: return "폰 찾기"
        case .showDate: return "오늘 날짜 확인"
        case .showBattery: return "배터리 잔량 표시"
        case .showSteps: return "걸음수 확인"
        case .musicPlayPause: return "음악: 재생/일시정지"
        case .musicNext: return "음악: 다음 곡"
        case .musicPrevious: return "음악: 이전 곡"
        case .recordLocation: return "위치 기록"
        case .randomDice: return "랜덤 주사위"
        case .iftttWebhook: return "IFTTT Webhook"
        case .shortcut: return "단축어 실행 (앱 열림)"
        case .urlRequest: return "URL 요청"
        }
    }

    var category: String {
        switch self {
        case .none: return ""
        case .findPhone, .showDate, .showBattery, .showSteps: return "기본"
        case .musicPlayPause, .musicNext, .musicPrevious: return "음악"
        case .recordLocation, .randomDice: return "재미"
        case .iftttWebhook, .shortcut, .urlRequest: return "고급"
        }
    }
}

struct WebhookPreset: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String = ""
    var baseURL: String = ""
}

struct ButtonAction: Codable, Equatable {
    var type: ButtonActionType = .none
    var iftttEventName: String = ""
    var shortcutName: String = ""
    var urlString: String = ""
    var urlPresetID: UUID? = nil
    var urlPath: String = ""
    var urlParams: String = ""
    var diceMax: Int = 6  // 주사위 최대값 (1...diceMax 범위에서 랜덤)
    var label: String = ""

    /// 실행 내역용 짧은 설명
    var summary: String {
        switch type {
        case .none: return "없음"
        case .findPhone: return "폰 찾기"
        case .showDate: return "날짜 확인"
        case .showBattery: return "배터리"
        case .showSteps: return "걸음수"
        case .musicPlayPause: return "재생/일시정지"
        case .musicNext: return "다음 곡"
        case .musicPrevious: return "이전 곡"
        case .recordLocation: return "위치 기록"
        case .randomDice: return "주사위 (1시–\(diceMax)시)"
        case .iftttWebhook: return "IFTTT: \(iftttEventName)"
        case .shortcut: return "단축어: \(shortcutName)"
        case .urlRequest: return label.isEmpty ? "URL 요청" : label
        }
    }
}

struct ButtonKey: Hashable, Codable {
    let button: Int   // 0=top, 2=bottom
    let event: Int    // 1=single, 2=long, 3=double, 4=triple, 5=quad

    var displayButton: String {
        button == 0 ? "상단" : "하단"
    }

    var displayEvent: String {
        switch event {
        case 1: return "1회 클릭"
        case 2: return "길게 누름"
        case 3: return "2회 클릭"
        case 4: return "3회 클릭"
        case 5: return "4회 클릭"
        default: return "코드 \(event)"
        }
    }

    var storageKey: String { "\(button)_\(event)" }
}

// MARK: - Manager

final class ButtonActionManager: ObservableObject {
    @Published var mappings: [String: ButtonAction] = [:]
    @Published var iftttKey: String = ""
    @Published var webhookPresets: [WebhookPreset] = []

    // 모스부호 입력 모드
    @Published var morseMappings: [String: ButtonAction] = [:]
    @Published var isMorseMode = false
    @Published var morseSymbolBuffer: [MorseSymbol] = []   // 현재 입력 중인 한 문자의 점/대시
    @Published var morseCommandBuffer: String = ""          // 확정된 문자들의 누적 문자열

    // 피드백 큐 (한 문자 확정 시마다 enqueue)
    private var feedbackQueue: [(symbols: [MorseSymbol], counterIndex: Int)] = []
    private var isFeedbackPlaying = false
    /// in-flight 피드백 콜백 무효화용 generation 카운터. 새 입력마다 +1, 콜백은 자기 시점 generation 일치시에만 진행.
    private var feedbackGeneration: Int = 0

    /// 모터별 single-flight 추적. 한 번에 BLE 명령을 하나만 보내고 다음은 모터가 물리적으로
    /// 완료된 뒤(motionEndTime 이후)에 송신. 펌웨어가 in-flight 명령을 preempt하면 물리 위치가
    /// 소프트웨어 target보다 뒤처지므로, preempt 자체를 만들지 않는 방식.
    private struct MotorTrack {
        var sentTarget: Int = 0          // 마지막으로 BLE에 송신한 절대 target (raw, 누적)
        var motionEndTime: TimeInterval = 0  // 그 동작의 물리 완료 예상 시각
        var pendingTarget: Int? = nil    // 모터 busy 중에 들어온 다음 target (덮어쓰기)
        var flushTask: DispatchWorkItem? = nil
    }
    private var hourTrack = MotorTrack()
    private var minuteTrack = MotorTrack()
    private static let secondsPerMark: Double = 0.1

    /// 모터별 마지막으로 의도한 위치 (mod 60). pending이 있으면 그 값 우선.
    /// 외부 코드(snap target 계산 등)는 이 값을 "곧 그 위치로 갈 거다"로 신뢰 가능.
    private var currentHourPos: Int {
        let raw = hourTrack.pendingTarget ?? hourTrack.sentTarget
        return ((raw % 60) + 60) % 60
    }
    private var currentMinutePos: Int {
        let raw = minuteTrack.pendingTarget ?? minuteTrack.sentTarget
        return ((raw % 60) + 60) % 60
    }
    /// 등록 가능한 모스 명령어 최대 길이 (시침 카운터 1시~11시 범위에 맞춤).
    static let morseMaxCommandLength = 11
    /// 모스모드 중 펌웨어가 recalibrate 모드 상태인지
    private var isRecalibrateActive = false

    let findMyPhone = FindMyPhone()
    @Published var isFindMyPhonePlaying = false
    private let musicController = MusicController()
    var locationRecorder: LocationRecorder?
    var bleManager: BLEManager?
    var historyManager: ActionHistoryManager?

    private static let mappingsKey = "button_mappings"
    private static let iftttKeyKey = "ifttt_webhook_key"
    private static let morseKey = "morse_mappings"
    private static let webhookPresetsKey = "webhook_presets"

    // 상단 전체 + 하단 1회/2회/3회/4회 (길게 누름 제외)
    static let allButtons: [ButtonKey] = {
        var keys: [ButtonKey] = []
        for event in [1, 3, 4, 5, 2] {
            keys.append(ButtonKey(button: 0, event: event))
        }
        // 하단: 길게 누름(2) 제외
        for event in [1, 3, 4, 5] {
            keys.append(ButtonKey(button: 2, event: event))
        }
        return keys
    }()

    init() {
        load()
    }

    func getAction(for key: ButtonKey) -> ButtonAction {
        mappings[key.storageKey] ?? ButtonAction()
    }

    func setAction(for key: ButtonKey, action: ButtonAction) {
        mappings[key.storageKey] = action
        save()
    }

    // MARK: - Execute

    func handleButtonEvent(button: Int, event: Int) {
        // 폰 찾기 재생 중엔 어떤 버튼 입력이든 정지로 흡수 — 매핑된 액션은 실행하지 않음.
        // event 12("길게 누름 끝")는 release artifact이므로 제외 — 길게 누름으로 폰 찾기를
        // 시작한 직후 손을 뗄 때 자기 자신을 즉시 정지시키는 것을 방지.
        if isFindMyPhonePlaying {
            if event != 12 {
                stopFindMyPhone()
            }
            return
        }

        // 모스모드 중 새 입력 도착 → 진행 중 피드백 무효화 + 누적 should-be 위치로 스냅.
        // 이렇게 해야 in-flight 콜백 체인이 BLE에 명령을 더 던지지 못하고, 다음 핸들러가
        // 일관된 바늘 위치(commandBuffer 누적 변위)에서 시작할 수 있음.
        if isMorseMode && isFeedbackPlaying {
            cancelInflightFeedback()
        }

        // 하단 길게 누름 → 모스모드 진입 또는 종료(명령 실행)
        if button == 2 && event == 2 {
            if isMorseMode {
                commitAndExecuteMorse()
            } else {
                startMorseMode()
            }
            return
        }

        // 모스모드 중 — 정의된 제스처만 처리
        if isMorseMode {
            handleMorseInput(button: button, event: event)
            return
        }

        // 일반 모드
        let key = ButtonKey(button: button, event: event)
        let action = getAction(for: key)
        historyManager?.record(
            trigger: "\(key.displayButton) \(key.displayEvent)",
            actionName: action.summary
        )
        executeAction(action)
    }

    func executeAction(_ action: ButtonAction) {
        switch action.type {
        case .none:
            break
        case .findPhone:
            handleFindMyPhone()
        case .showDate:
            showDateOnWatch()
        case .showBattery:
            showBatteryOnWatch()
        case .showSteps:
            showStepsOnWatch()
        case .musicPlayPause:
            musicController.playPause()
        case .musicNext:
            musicController.nextTrack()
        case .musicPrevious:
            musicController.previousTrack()
        case .recordLocation:
            locationRecorder?.recordCurrentLocation()
        case .randomDice:
            rollRandomDice(max: max(2, action.diceMax))
        case .iftttWebhook:
            fireIFTTT(eventName: action.iftttEventName)
        case .shortcut:
            runShortcut(name: action.shortcutName)
        case .urlRequest:
            fireURL(urlString: resolvedURL(for: action))
        }
    }

    func handleFindMyPhone() {
        findMyPhone.play()
        isFindMyPhonePlaying = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            self?.stopFindMyPhone()
        }
    }

    func stopFindMyPhone() {
        findMyPhone.stop()
        isFindMyPhonePlaying = false
    }

    // MARK: - Morse Input Mode

    private func startMorseMode() {
        isMorseMode = true
        morseSymbolBuffer = []
        morseCommandBuffer = ""
        feedbackQueue.removeAll()
        isFeedbackPlaying = false
        resetMotorTracks()
        // 진동 1회 — 시작
        bleManager?.sendCommand(name: "vibrator_start", value: [150])
        // 크라운 complication 비활성화 (모스모드 중 실수 방지)
        bleManager?.sendCommand(name: "complications", value: [5, 15, 18])
        // 캘리브레이션 진입 → 펌웨어가 바늘을 0(12시)으로 자동 이동
        bleManager?.sendCommand(name: "recalibrate", value: true)
        isRecalibrateActive = true
        bleManager?.log("모스모드 시작 → 0시 (recalibrate)")
    }

    private static let crownModeKey = "kronaby_crown_mode"

    private func restoreCrownComplication() {
        let mode = UserDefaults.standard.integer(forKey: Self.crownModeKey)
        bleManager?.sendCommand(name: "complications", value: [5, mode, 18])
        bleManager?.log("크라운 복원: mode \(mode)")
    }

    /// recalibrate 모드에서 바늘을 절대 위치(분 틱 0~59)로 이동 — single-flight 큐.
    /// 펌웨어 `recalibrate_move(motor, stepDelta)`는 모터 스텝 단위 — 분침 3 step/분, 시침 2 step/분.
    /// 양 모터 모두 음수 delta 지원 → 반시계 회전.
    private static let stepsPerMinuteMarkHour = 2   // motor 0
    private static let stepsPerMinuteMarkMinute = 3 // motor 1

    /// 펌웨어에 즉시 송신 (sentTarget·motionEndTime 갱신).
    private func sendMotorNow(motor: Int, rawTarget: Int) {
        let track = motor == 0 ? hourTrack : minuteTrack
        let delta = rawTarget - track.sentTarget
        if delta == 0 {
            clearPending(motor)
            return
        }
        let scale = motor == 0 ? Self.stepsPerMinuteMarkHour : Self.stepsPerMinuteMarkMinute
        bleManager?.sendCommand(name: "recalibrate_move", value: [motor, delta * scale])
        let now = Date().timeIntervalSinceReferenceDate
        // 0.1s 안전 마진 — 실제 모터 속도가 추정보다 느릴 때 다음 명령이 preempt되지 않도록.
        let endTime = now + Double(abs(delta)) * Self.secondsPerMark + 0.1
        if motor == 0 {
            hourTrack.sentTarget = rawTarget
            hourTrack.motionEndTime = endTime
            hourTrack.pendingTarget = nil
            hourTrack.flushTask = nil
        } else {
            minuteTrack.sentTarget = rawTarget
            minuteTrack.motionEndTime = endTime
            minuteTrack.pendingTarget = nil
            minuteTrack.flushTask = nil
        }
    }

    private func clearPending(_ motor: Int) {
        if motor == 0 {
            hourTrack.pendingTarget = nil
            hourTrack.flushTask?.cancel()
            hourTrack.flushTask = nil
        } else {
            minuteTrack.pendingTarget = nil
            minuteTrack.flushTask?.cancel()
            minuteTrack.flushTask = nil
        }
    }

    /// pending이 있으면 모터 idle 시점에 송신 (즉시 또는 task 예약).
    private func scheduleFlush(_ motor: Int) {
        let track = motor == 0 ? hourTrack : minuteTrack
        guard let pending = track.pendingTarget else { return }
        let now = Date().timeIntervalSinceReferenceDate
        if motor == 0 { hourTrack.flushTask?.cancel(); hourTrack.flushTask = nil }
        else { minuteTrack.flushTask?.cancel(); minuteTrack.flushTask = nil }
        if now >= track.motionEndTime {
            sendMotorNow(motor: motor, rawTarget: pending)
            return
        }
        let delay = track.motionEndTime - now
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let t = motor == 0 ? self.hourTrack : self.minuteTrack
            if let p = t.pendingTarget {
                self.sendMotorNow(motor: motor, rawTarget: p)
            }
        }
        if motor == 0 { hourTrack.flushTask = task } else { minuteTrack.flushTask = task }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
    }

    /// 절대 mod-60 위치 (0~59)로 이동 — shortest path delta. 모터 트랙에 큐잉.
    private func moveHand(motor: Int, to target: Int) {
        let track = motor == 0 ? hourTrack : minuteTrack
        let currentRaw = track.pendingTarget ?? track.sentTarget
        let currentMod = ((currentRaw % 60) + 60) % 60
        let targetMod = ((target % 60) + 60) % 60
        var delta = targetMod - currentMod
        if delta > 30 { delta -= 60 }
        else if delta < -30 { delta += 60 }
        if delta == 0 { return }
        let newRaw = currentRaw + delta
        if motor == 0 { hourTrack.pendingTarget = newRaw } else { minuteTrack.pendingTarget = newRaw }
        scheduleFlush(motor)
    }

    private func handleMorseInput(button: Int, event: Int) {
        switch (button, event) {
        case (2, 1):  // 하단 1회 → 점
            appendMorseSymbol(.dot)
        case (2, 3):  // 하단 2회 → 대시
            appendMorseSymbol(.dash)
        case (0, 1):  // 상단 1회 → 한 문자 확정
            confirmMorseChar()
        case (0, 3):  // 상단 2회 → 점진 취소 (symbol → 1자 → 빈 상태 진동)
            cancelStepwise()
        case (0, 2):  // 상단 길게 → 전체 취소
            cancelAll()
        default:
            // 그 외 입력은 모스모드 중엔 무시
            bleManager?.log("모스모드: 무시된 입력 (button=\(button), event=\(event))")
        }
    }

    private func appendMorseSymbol(_ symbol: MorseSymbol) {
        morseSymbolBuffer.append(symbol)
        bleManager?.log("모스 심볼: \(MorseDecoder.symbolString(morseSymbolBuffer))")
    }

    private func confirmMorseChar() {
        guard !morseSymbolBuffer.isEmpty else {
            bleManager?.log("모스: 빈 심볼 버퍼 — 확정 무시")
            return
        }

        // 한도 초과 (시침 카운터 범위 보호)
        guard morseCommandBuffer.count < Self.morseMaxCommandLength else {
            let symbols = morseSymbolBuffer
            morseSymbolBuffer.removeAll()
            bleManager?.sendCommand(name: "vibrator_start", value: [200, 100, 200])
            bleManager?.log("모스 한도 초과 (\(Self.morseMaxCommandLength)자): \(MorseDecoder.symbolString(symbols)) 무시")
            return
        }

        let symbols = morseSymbolBuffer
        morseSymbolBuffer.removeAll()

        guard let char = MorseDecoder.decode(symbols) else {
            // 인식 실패: 진동 2회 + 분침 흔들기
            bleManager?.sendCommand(name: "vibrator_start", value: [100, 80, 100])
            bleManager?.log("모스 인식 실패: \(MorseDecoder.symbolString(symbols))")
            shakeForError()
            return
        }

        morseCommandBuffer.append(char)
        bleManager?.log("모스 문자 확정: \(char) (\(MorseDecoder.symbolString(symbols))) → 누적 \"\(morseCommandBuffer)\"")
        enqueueFeedback(symbols: symbols, counterIndex: morseCommandBuffer.count)
    }

    /// 상단 2회 — 점진 취소: symbolBuffer → 1자 삭제 → 빈 상태 진동 2회
    private func cancelStepwise() {
        if !morseSymbolBuffer.isEmpty {
            morseSymbolBuffer.removeAll()
            bleManager?.sendCommand(name: "vibrator_start", value: [100])
            bleManager?.log("모스 점진 취소: 심볼 버퍼 삭제")
        } else if !morseCommandBuffer.isEmpty {
            bleManager?.sendCommand(name: "vibrator_start", value: [100])
            morseCommandBuffer.removeLast()
            bleManager?.log("모스 점진 취소: 1자 삭제 → 누적 \"\(morseCommandBuffer)\"")
            // 분침: 누적 변위 (mod 60), 시침: 글자 수 × 5. 둘 다 새 누적 상태로 직접 이동.
            moveHand(motor: 1, to: minuteDisplacementForCommandBuffer())
            moveHand(motor: 0, to: morseCommandBuffer.count * 5)
        } else {
            bleManager?.sendCommand(name: "vibrator_start", value: [100, 80, 100])
            bleManager?.log("모스 점진 취소: 빈 상태 — 진동 2회")
        }
    }

    /// 상단 길게 — 전체 취소: 두 버퍼 모두 비우고 양 바늘 0 복귀
    private func cancelAll() {
        if !morseSymbolBuffer.isEmpty || !morseCommandBuffer.isEmpty {
            morseSymbolBuffer.removeAll()
            morseCommandBuffer.removeAll()
            bleManager?.sendCommand(name: "vibrator_start", value: [200])
            bleManager?.log("모스 전체 취소")
            moveHand(motor: 1, to: 0)
            moveHand(motor: 0, to: 0)
        } else {
            bleManager?.sendCommand(name: "vibrator_start", value: [100, 80, 100])
            bleManager?.log("모스 전체 취소: 빈 상태 — 진동 2회")
        }
    }

    /// 모스 명령어 누적 버퍼의 분침 총 변위 (mod 60). 점=5, 대시=10. 글자 간 0 복귀 없음.
    private func minuteDisplacementForCommandBuffer() -> Int {
        var total = 0
        for char in morseCommandBuffer {
            guard let symbols = MorseDecoder.encode(char) else { continue }
            for sym in symbols {
                total += (sym == .dot ? 5 : 10)
            }
        }
        return total % 60
    }

    /// 진행 중 피드백 콜백 체인을 무효화하고 should-be 위치로 스냅(큐잉).
    /// generation 증가 → 향후 fired async 콜백은 mismatch로 조기 종료.
    /// 큐 비우기 + (분침=누적 변위, 시침=count×5)로 모터 트랙에 큐잉. single-flight라
    /// 모터가 이전 동작을 끝낸 뒤 snap 명령을 송신하므로 별도 deadline 트래킹 불필요.
    private func cancelInflightFeedback() {
        feedbackGeneration += 1
        feedbackQueue.removeAll()
        isFeedbackPlaying = false
        let hourTarget = morseCommandBuffer.count * 5
        let minuteTarget = minuteDisplacementForCommandBuffer()
        moveHand(motor: 1, to: minuteTarget)
        moveHand(motor: 0, to: hourTarget)
    }

    private func commitAndExecuteMorse() {
        let key = morseCommandBuffer.uppercased()
        morseSymbolBuffer.removeAll()
        morseCommandBuffer.removeAll()
        feedbackQueue.removeAll()

        // 모터들이 pending+motion 끝낼 때까지 대기, 그 후 액션 실행. single-flight라
        // bothMotorsIdleTime이 정확한 종료 시각을 알려줌.
        let now = Date().timeIntervalSinceReferenceDate
        let wait = Swift.max(0.3, bothMotorsIdleTime() - now + 0.3)
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
            guard let self else { return }
            self.runMorseExecution(key: key)
        }
    }

    private func runMorseExecution(key: String) {
        if key.isEmpty {
            // 빈 버퍼 종료 — 단순 취소
            bleManager?.sendCommand(name: "vibrator_start", value: [100])
            bleManager?.log("모스모드 종료: 빈 버퍼")
            finalizeMorseExit()
            return
        }

        let action = morseMappings[key] ?? ButtonAction()
        if action.type == .none {
            // 미등록 명령
            bleManager?.sendCommand(name: "vibrator_start", value: [200, 100, 200, 100, 200])
            historyManager?.record(trigger: "모스 [\(key)]", actionName: "미등록")
            bleManager?.log("모스 명령 미등록: [\(key)]")
            finalizeMorseExit()
            return
        }

        // 등록된 명령 실행
        bleManager?.sendCommand(name: "vibrator_start", value: [150, 100, 150])
        historyManager?.record(trigger: "모스 [\(key)]", actionName: action.summary)
        bleManager?.log("모스 명령 실행: [\(key)] → \(action.type.displayName)")

        // 표시 액션·주사위는 recalibrate 유지한 채 실행 (executeDisplayAction/rollDiceInRecalibrate 끝에 exitRecalibrate),
        // 그 외는 즉시 exitRecalibrate 후 액션 실행.
        isMorseMode = false
        restoreCrownComplication()
        if action.type == .showDate || action.type == .showBattery || action.type == .showSteps {
            executeDisplayAction(action)
        } else if action.type == .randomDice {
            rollDiceInRecalibrate(max: max(2, action.diceMax))
        } else {
            exitRecalibrateAndSyncTime()
            executeAction(action)
        }
    }

    /// 모스모드를 액션 실행 없이 단순 종료 (recalibrate 해제 + 시간 복귀)
    /// commitAndExecuteMorse가 cancelInflight 후 충분히 대기하므로 즉시 호출 가능.
    private func finalizeMorseExit() {
        isMorseMode = false
        feedbackQueue.removeAll()
        restoreCrownComplication()
        exitRecalibrateAndSyncTime()
    }

    /// recalibrate(false) 직전에 양 바늘을 0(12시)으로 복귀시킨 뒤 종료 + datetime 전송.
    /// single-flight 큐 → 양 모터가 모든 pending 동작을 끝내고 0에 도달한 뒤 recalibrate(false) 송신.
    private func exitRecalibrateAndSyncTime() {
        moveHand(motor: 0, to: 0)
        moveHand(motor: 1, to: 0)
        let now = Date().timeIntervalSinceReferenceDate
        let waitTime = Swift.max(0.5, bothMotorsIdleTime() - now + 0.5)
        DispatchQueue.main.asyncAfter(deadline: .now() + waitTime) { [weak self] in
            guard let self else { return }
            self.bleManager?.sendCommand(name: "recalibrate", value: false)
            self.isRecalibrateActive = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.sendCurrentDatetime()
            }
        }
    }

    // MARK: - Morse Feedback Queue

    private func enqueueFeedback(symbols: [MorseSymbol], counterIndex: Int) {
        feedbackQueue.append((symbols, counterIndex))
        if !isFeedbackPlaying { drainFeedbackQueue() }
    }

    private func drainFeedbackQueue() {
        guard !feedbackQueue.isEmpty else {
            isFeedbackPlaying = false
            return
        }
        isFeedbackPlaying = true
        let item = feedbackQueue.removeFirst()
        playFeedback(symbols: item.symbols, counterIndex: item.counterIndex) { [weak self] in
            self?.drainFeedbackQueue()
        }
    }

    /// 한 문자 피드백: 분침을 누적적으로 +5(점)/+10(대시)씩 이동(0 복귀 없음, mod 60), 그 뒤 시침 → counterIndex×5 직접 이동.
    /// generation 일치 검사로 in-flight 콜백 체인 무효화 가능.
    private func playFeedback(symbols: [MorseSymbol], counterIndex: Int, onComplete: @escaping () -> Void) {
        let gen = feedbackGeneration
        playSymbolSequence(symbols: symbols, index: 0, generation: gen) { [weak self] in
            guard let self, gen == self.feedbackGeneration else { return }
            self.moveHand(motor: 0, to: counterIndex * 5)
            // single-flight: 시침 모터의 idle 시각까지 대기 후 onComplete (다음 char drain).
            let now = Date().timeIntervalSinceReferenceDate
            let waitTime = Swift.max(0.3, self.motorIdleTime(0) - now + 0.3)
            DispatchQueue.main.asyncAfter(deadline: .now() + waitTime) { [weak self] in
                guard let self, gen == self.feedbackGeneration else { return }
                onComplete()
            }
        }
    }

    /// 심볼 하나씩 분침에 누적 가산 (점=+5, 대시=+10). 0 복귀 없이 그대로 다음 심볼로 이동.
    private func playSymbolSequence(symbols: [MorseSymbol], index: Int, generation: Int, onComplete: @escaping () -> Void) {
        guard index < symbols.count else {
            onComplete()
            return
        }
        let increment = symbols[index] == .dot ? 5 : 10
        moveHandRelative(motor: 1, byMarks: increment)
        let travel = estimatedTravelTime(from: 0, to: increment)
        DispatchQueue.main.asyncAfter(deadline: .now() + travel + 0.25) { [weak self] in
            guard let self, generation == self.feedbackGeneration else { return }
            self.playSymbolSequence(symbols: symbols, index: index + 1, generation: generation, onComplete: onComplete)
        }
    }

    /// 현재 위치에서 ±delta 분 마크 누적 이동. 양수=시계방향, 음수=반시계. 모터 트랙에 큐잉.
    private func moveHandRelative(motor: Int, byMarks delta: Int) {
        guard delta != 0 else { return }
        let track = motor == 0 ? hourTrack : minuteTrack
        let currentRaw = track.pendingTarget ?? track.sentTarget
        let newRaw = currentRaw + delta
        if motor == 0 { hourTrack.pendingTarget = newRaw } else { minuteTrack.pendingTarget = newRaw }
        scheduleFlush(motor)
    }

    /// 절대 target으로 시계방향(forward)만 이동. 룰렛 스핀처럼 항상 시계방향이어야 하는 경로용.
    private func moveHandForward(motor: Int, to target: Int) {
        let track = motor == 0 ? hourTrack : minuteTrack
        let currentRaw = track.pendingTarget ?? track.sentTarget
        let currentMod = ((currentRaw % 60) + 60) % 60
        let targetMod = ((target % 60) + 60) % 60
        var delta = targetMod - currentMod
        if delta < 0 { delta += 60 }  // forward only
        if delta == 0 { return }
        let newRaw = currentRaw + delta
        if motor == 0 { hourTrack.pendingTarget = newRaw } else { minuteTrack.pendingTarget = newRaw }
        scheduleFlush(motor)
    }

    /// 모터 트랙 초기화 — recalibrate(true) 직후 (펌웨어가 양 바늘을 0으로 정렬).
    private func resetMotorTracks() {
        hourTrack.flushTask?.cancel()
        minuteTrack.flushTask?.cancel()
        hourTrack = MotorTrack()
        minuteTrack = MotorTrack()
    }

    /// 모터별 pending까지 모두 끝나는 시각 (현재 motion + 큐잉된 pending 동작).
    private func motorIdleTime(_ motor: Int) -> TimeInterval {
        let track = motor == 0 ? hourTrack : minuteTrack
        let now = Date().timeIntervalSinceReferenceDate
        let basicEnd = max(now, track.motionEndTime)
        if let pending = track.pendingTarget {
            let delta = abs(pending - track.sentTarget)
            return basicEnd + Double(delta) * Self.secondsPerMark
        }
        return basicEnd
    }

    /// 양 모터가 모두 idle인 시각.
    private func bothMotorsIdleTime() -> TimeInterval {
        max(motorIdleTime(0), motorIdleTime(1))
    }

    /// 인식 실패 시 분침을 누적 위치 주변에서 흔들고 원위치 복귀. ±5 / -10 / +5 → net 0.
    private func shakeForError() {
        guard isRecalibrateActive else { return }
        moveHandRelative(motor: 1, byMarks: 5)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.moveHandRelative(motor: 1, byMarks: -10)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.moveHandRelative(motor: 1, byMarks: 5)
            }
        }
    }

    // MARK: - Hand Movement

    /// 바늘 이동에 필요한 예상 시간 (마크 단위 거리 기반, 최소 1초).
    /// 음수 delta 직진 회전이므로 abs(to - from)이 곧 회전 마크 수.
    /// 0.1s/mark는 실측 보수 추정 — 펌웨어가 in-flight 명령 위에 다음 명령을 덮어쓰는 것으로
    /// 보이므로 다음 명령 발화 전에 실제 모터 동작이 끝나야 함. 너무 짧게 잡으면 snap→exit 같은
    /// 연쇄 이동에서 종료 위치가 어긋남.
    private func estimatedTravelTime(from: Int, to: Int) -> Double {
        let distance = abs(to - from)
        return max(1.0, Double(distance) * 0.1)
    }

    // MARK: - Random Dice

    private var isDiceRolling = false

    /// 다이얼 위치 스케일 (0–59) 기준 시(hour) 마크 위치.
    /// face 1=5, face 2=10, ... face 11=55, face 12=0.
    private func hourMarkPosition(_ face: Int) -> Int {
        (face * 5) % 60
    }

    /// 버튼 직접 매핑 경로 — recalibrate 진입부터 시작.
    /// 펌웨어가 진입 시 바늘을 0으로 자동 이동 → onComplete 후 추적값 0으로 동기화.
    /// 시작 위치 불명(현재 시각 어디든) → 보수적으로 2초 대기.
    private func rollRandomDice(max: Int) {
        guard !isDiceRolling else {
            bleManager?.log("주사위 중복 실행 무시")
            return
        }
        guard bleManager?.connectionState == .connected else {
            bleManager?.log("주사위 실패 — 미연결")
            return
        }
        isDiceRolling = true
        bleManager?.sendCommand(name: "recalibrate", value: true, onComplete: { [weak self] in
            guard let self else { return }
            self.isRecalibrateActive = true
            self.resetMotorTracks()
            self.startDiceRoll(travelToZero: 2.0, max: max)
        })
    }

    /// 모스 경로 — recalibrate 이미 활성, 바늘이 (currentHourPos, currentMinutePos)에 있음.
    /// 음수 delta로 0 복귀 후 스핀. single-flight: 모터가 0에 도달할 때까지 motorIdleTime 대기.
    private func rollDiceInRecalibrate(max: Int) {
        guard !isDiceRolling else {
            bleManager?.log("주사위 중복 실행 무시")
            return
        }
        isDiceRolling = true
        moveHand(motor: 0, to: 0)
        moveHand(motor: 1, to: 0)
        let now = Date().timeIntervalSinceReferenceDate
        let travel = Swift.max(1.0, bothMotorsIdleTime() - now)
        startDiceRoll(travelToZero: travel, max: max)
    }

    /// 12시 도착 대기(travelToZero) → 1초 후 진동 1회 → 1초 후 스핀.
    private func startDiceRoll(travelToZero: Double, max: Int) {
        // 도착까지 이동시간 + 1초 뒤 진동
        DispatchQueue.main.asyncAfter(deadline: .now() + travelToZero + 1.0) { [weak self] in
            self?.bleManager?.sendCommand(name: "vibrator_start", value: [150])
            self?.bleManager?.log("주사위: 12시 도착 → 진동 후 스핀 준비")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.animateDiceSpin(max: max)
            }
        }
    }

    /// 바늘을 빠르게 돌리다 점점 느려지며 결과값에서 정지.
    /// 시침(motor 0)은 12시에 고정, 분침(motor 1)만 회전 — 룰렛 비주얼.
    /// 각 face는 다이얼 0–59 스케일에서 `face × 5 % 60` 위치 (시 마크)를 가리킴.
    private func animateDiceSpin(max diceMax: Int) {
        let finalResult = Int.random(in: 1...diceMax)
        bleManager?.log("주사위 스핀 시작 (1–\(diceMax)) → 결과: \(finalResult)")

        // 1.5바퀴 + 결과값 — 풀 사이클 + 부분 사이클로 구성
        var sequence: [Int] = []
        for p in 1...diceMax { sequence.append(p) }
        for p in 1...finalResult { sequence.append(p) }

        let totalSteps = sequence.count

        // 연속 감속 곡선 — 전 구간에 걸쳐 점진적으로 느려지도록.
        // 범위 0.15 → 1.15 (약 7.6배), 지수 2.5로 후반부 가중.
        // 스핀 내내 "점점 느려진다" 감각 유지, 끝에서 자연스럽게 착지.
        var delay: Double = 0
        for (i, face) in sequence.enumerated() {
            let progress = Double(i) / Double(Swift.max(totalSteps - 1, 1))
            let interval = 0.15 + pow(progress, 2.5) * 1.0
            let position = hourMarkPosition(face)

            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                // 분침(motor 1)만 시계방향 누적 이동 — 시침은 인트로에서 12시로 정렬된 상태 유지.
                // 룰렛은 항상 forward이므로 wrap 거리로 송신 (예: 50→5는 +15마크).
                self?.moveHandForward(motor: 1, to: position)
            }
            delay += interval
        }

        // 도착 후 잠시 대기 → 진동 1회
        let vibrateAt = delay + 1.0
        DispatchQueue.main.asyncAfter(deadline: .now() + vibrateAt) { [weak self] in
            self?.bleManager?.sendCommand(name: "vibrator_start", value: [300])
            self?.bleManager?.log("주사위 결과: \(finalResult) (진동)")
        }

        // 결과 표시 후 시계 모드 복귀
        DispatchQueue.main.asyncAfter(deadline: .now() + vibrateAt + 2.5) { [weak self] in
            guard let self else { return }
            self.exitRecalibrateAndSyncTime()
            self.isDiceRolling = false
        }
    }

    private func sendCurrentDatetime() {
        let now = Date()
        var cal = Calendar.current
        cal.timeZone = .current
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second, .weekday], from: now)
        let kronabyDay: Int
        switch c.weekday! {
        case 1: kronabyDay = 5
        case 2: kronabyDay = 6
        case 3: kronabyDay = 0
        case 4: kronabyDay = 1
        case 5: kronabyDay = 2
        case 6: kronabyDay = 3
        case 7: kronabyDay = 4
        default: kronabyDay = 0
        }
        bleManager?.sendCommand(name: "datetime", value: [c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!, kronabyDay])
    }

    // MARK: - Watch Display Actions

    /// 표시 액션의 목표 위치 계산
    private func displayPositions(for action: ButtonAction) -> (hour: Int, minute: Int) {
        switch action.type {
        case .showDate:
            let comps = Calendar.current.dateComponents([.month, .day], from: Date())
            let month = comps.month ?? 1
            let day = comps.day ?? 1
            return (month * 5 % 60, day)
        case .showBattery:
            let percent = bleManager?.batteryInfo?[0] ?? 0
            let pos = Int(Double(percent) / 100.0 * 59.0)
            return (pos, pos)
        case .showSteps:
            let steps = bleManager?.stepsInfo?[0] ?? 0
            let goal = UserDefaults.standard.integer(forKey: "kronaby_step_goal_v2")
            let effectiveGoal = goal > 0 ? goal : 5000
            let ratio = min(Double(steps) / Double(effectiveGoal), 1.0)
            let pos = Int(ratio * 59.0)
            return (pos, pos)
        default:
            return (0, 0)
        }
    }

    /// 표시 액션 로그 메시지
    private func displayLogMessage(for action: ButtonAction, hourPos: Int, minutePos: Int) {
        switch action.type {
        case .showDate:
            let comps = Calendar.current.dateComponents([.month, .day], from: Date())
            bleManager?.log("날짜 표시: \(comps.month ?? 0)월 \(comps.day ?? 0)일 (시침→\(hourPos), 분침→\(minutePos))")
        case .showBattery:
            let percent = bleManager?.batteryInfo?[0] ?? 0
            bleManager?.log("배터리 표시: \(percent)% → \(minutePos)분 위치")
        case .showSteps:
            let steps = bleManager?.stepsInfo?[0] ?? 0
            let goal = UserDefaults.standard.integer(forKey: "kronaby_step_goal_v2")
            bleManager?.log("걸음수 표시: \(steps)/\(goal > 0 ? goal : 5000) → \(minutePos)분 위치")
        default: break
        }
    }

    /// recalibrate 활성 상태에서 표시 액션 실행 → 일정 시간 후 종료.
    /// single-flight: 모터 트랙이 실제 바늘 위치 추적. moveHand로 큐잉만 하면 모터가 알아서 처리.
    private func executeDisplayAction(_ action: ButtonAction) {
        let (hourPos, minutePos) = displayPositions(for: action)
        displayLogMessage(for: action, hourPos: hourPos, minutePos: minutePos)
        moveHand(motor: 0, to: hourPos)
        moveHand(motor: 1, to: minutePos)
        let now = Date().timeIntervalSinceReferenceDate
        let displayWait = Swift.max(3.0, bothMotorsIdleTime() - now + 3.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + displayWait) { [weak self] in
            self?.exitRecalibrateAndSyncTime()
        }
    }

    /// 직접 버튼에서 호출 — recalibrate 진입부터 시작
    private func showDateOnWatch() { showDisplayOnWatch(.showDate) }
    private func showBatteryOnWatch() { showDisplayOnWatch(.showBattery) }
    private func showStepsOnWatch() { showDisplayOnWatch(.showSteps) }

    private func showDisplayOnWatch(_ type: ButtonActionType) {
        let action = ButtonAction(type: type)

        // recalibrate(true) → onComplete 후 펌웨어가 0시로 이동하는 시간 대기 → 모터 트랙 0 동기화 → 표시.
        bleManager?.sendCommand(name: "recalibrate", value: true, onComplete: { [weak self] in
            guard let self else { return }
            self.isRecalibrateActive = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self else { return }
                self.resetMotorTracks()
                self.executeDisplayAction(action)
            }
        })
    }

    // MARK: - IFTTT

    private func fireIFTTT(eventName: String) {
        guard !iftttKey.isEmpty, !eventName.isEmpty else { return }
        let urlStr = "https://maker.ifttt.com/trigger/\(eventName)/with/key/\(iftttKey)"
        guard let url = URL(string: urlStr) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        URLSession.shared.dataTask(with: request).resume()
    }

    // MARK: - Shortcuts

    private func runShortcut(name: String) {
        guard !name.isEmpty else { return }
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        if let url = URL(string: "shortcuts://run-shortcut?name=\(encoded)") {
            DispatchQueue.main.async {
                UIApplication.shared.open(url)
            }
        }
    }

    // MARK: - URL Request

    func resolvedURL(for action: ButtonAction) -> String {
        if let presetID = action.urlPresetID,
           let preset = webhookPresets.first(where: { $0.id == presetID }) {
            var url = preset.baseURL
            if !action.urlPath.isEmpty {
                url += action.urlPath.hasPrefix("/") ? action.urlPath : "/" + action.urlPath
            }
            if !action.urlParams.isEmpty {
                url += "?" + action.urlParams
            }
            return url
        }
        return action.urlString
    }

    func saveWebhookPresets() {
        if let data = try? JSONEncoder().encode(webhookPresets) {
            UserDefaults.standard.set(data, forKey: Self.webhookPresetsKey)
        }
    }

    private func fireURL(urlString: String) {
        guard let url = URL(string: urlString) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        URLSession.shared.dataTask(with: request).resume()
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(mappings) {
            UserDefaults.standard.set(data, forKey: Self.mappingsKey)
        }
        UserDefaults.standard.set(iftttKey, forKey: Self.iftttKeyKey)
        if let data = try? JSONEncoder().encode(morseMappings) {
            UserDefaults.standard.set(data, forKey: Self.morseKey)
        }
        if let data = try? JSONEncoder().encode(webhookPresets) {
            UserDefaults.standard.set(data, forKey: Self.webhookPresetsKey)
        }
    }

    func load() {
        if let data = UserDefaults.standard.data(forKey: Self.mappingsKey),
           let decoded = try? JSONDecoder().decode([String: ButtonAction].self, from: data) {
            mappings = decoded
        }
        iftttKey = UserDefaults.standard.string(forKey: Self.iftttKeyKey) ?? ""
        if let data = UserDefaults.standard.data(forKey: Self.morseKey),
           let decoded = try? JSONDecoder().decode([String: ButtonAction].self, from: data) {
            morseMappings = decoded
        }
        if let data = UserDefaults.standard.data(forKey: Self.webhookPresetsKey),
           let decoded = try? JSONDecoder().decode([WebhookPreset].self, from: data) {
            webhookPresets = decoded
        }
    }

    func saveMorse() {
        if let data = try? JSONEncoder().encode(morseMappings) {
            UserDefaults.standard.set(data, forKey: Self.morseKey)
        }
    }
}