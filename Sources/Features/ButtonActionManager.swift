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

struct ButtonAction: Codable, Equatable {
    var type: ButtonActionType = .none
    var iftttEventName: String = ""
    var shortcutName: String = ""
    var urlString: String = ""
    var diceMax: Int = 6  // 주사위 최대값 (1...diceMax 범위에서 랜덤)

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
        case .urlRequest: return "URL 요청"
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
    /// 모스모드 중 바늘 절대 위치 추적 (0~59 눈금, recalibrate_move 용 delta 계산).
    /// recalibrate(true) 직후엔 펌웨어가 양 바늘을 0으로 정렬.
    private var currentHourPos: Int = 0
    private var currentMinutePos: Int = 0
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
            fireURL(urlString: action.urlString)
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
        currentHourPos = 0
        currentMinutePos = 0
        // 진동 1회 — 시작
        bleManager?.sendCommand(name: "vibrator_start", value: [150])
        // 캘리브레이션 진입 → 펌웨어가 바늘을 0(12시)으로 자동 이동
        bleManager?.sendCommand(name: "recalibrate", value: true)
        isRecalibrateActive = true
        bleManager?.log("모스모드 시작 → 0시 (recalibrate)")
    }

    /// recalibrate 모드에서 한쪽 바늘을 절대 위치(분 틱 0~59)로 이동.
    /// 내부 추적은 분 틱 단위지만 펌웨어 `recalibrate_move`는 모터 스텝 단위 → 송신 시 변환.
    /// 실측: 분침 15 step → 5분, 시침 15 step → 7.5분. 두 모터 기어비가 달라 분당 스텝 다름.
    /// 분침: 3 step/분, 시침: 2 step/분.
    private static let stepsPerMinuteMarkHour = 2   // motor 0
    private static let stepsPerMinuteMarkMinute = 3 // motor 1
    private func moveHand(motor: Int, to target: Int) {
        let current = motor == 0 ? currentHourPos : currentMinutePos
        let delta = target - current
        guard delta != 0 else { return }
        let scale = motor == 0 ? Self.stepsPerMinuteMarkHour : Self.stepsPerMinuteMarkMinute
        let stepDelta = delta * scale
        bleManager?.sendCommand(name: "recalibrate_move", value: [motor, stepDelta])
        if motor == 0 { currentHourPos = target } else { currentMinutePos = target }
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

    /// 진행 중 피드백 콜백 체인을 무효화하고 should-be 위치로 스냅.
    /// generation 증가 → 향후 fired async 콜백은 mismatch로 조기 종료.
    /// 큐 비우기 + isFeedbackPlaying=false + (분침=누적 변위, 시침=count×5)로 절대 이동.
    private func cancelInflightFeedback() {
        feedbackGeneration += 1
        feedbackQueue.removeAll()
        isFeedbackPlaying = false
        moveHand(motor: 1, to: minuteDisplacementForCommandBuffer())
        moveHand(motor: 0, to: morseCommandBuffer.count * 5)
    }

    private func commitAndExecuteMorse() {
        let key = morseCommandBuffer.uppercased()
        morseSymbolBuffer.removeAll()
        morseCommandBuffer.removeAll()
        feedbackQueue.removeAll()

        // 직전 cancelInflightFeedback가 BLE 큐에 스냅 명령(분침/시침 → should-be)을 넣었을 수 있음.
        // 그게 펌웨어에서 처리될 시간을 확보한 뒤 종료 시퀀스 진행 — 그렇지 않으면
        // exitRecalibrate의 0,0 이동이 in-flight 명령들과 섞여 위치가 어긋남.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
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

        // 표시 액션은 recalibrate 유지한 채 실행, 그 외는 종료 후 실행
        if action.type == .showDate || action.type == .showBattery || action.type == .showSteps {
            isMorseMode = false
            isRecalibrateActive = false
            executeDisplayAction(action, fromPosition: max(currentHourPos, currentMinutePos))
        } else if action.type == .randomDice {
            isMorseMode = false
            isRecalibrateActive = false
            rollDiceInRecalibrate(max: max(2, action.diceMax), fromPosition: max(currentHourPos, currentMinutePos))
        } else {
            isMorseMode = false
            exitRecalibrateAndSyncTime()
            isRecalibrateActive = false
            executeAction(action)
        }
    }

    /// 모스모드를 액션 실행 없이 단순 종료 (recalibrate 해제 + 시간 복귀)
    private func finalizeMorseExit() {
        isMorseMode = false
        feedbackQueue.removeAll()
        // 진행 중인 피드백이 끝날 때까지 잠시 대기 후 종료 (피드백 중단 시 바늘이 어색하게 멈출 수 있음)
        let delay: Double = isFeedbackPlaying ? 0.5 : 0.0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.exitRecalibrateAndSyncTime()
            self.isRecalibrateActive = false
        }
    }

    /// recalibrate(false) 직전에 양 바늘을 0(12시)으로 복귀시킨 뒤 종료 + datetime 전송.
    /// 시침이 카운터 위치(N×5분)에 남은 채로 종료하면 펌웨어가 오프셋을 복원하지 못해
    /// 시각 표시가 그만큼 틀어짐(분침은 매 심볼 끝마다 0 복귀라 영향 없음).
    private func exitRecalibrateAndSyncTime() {
        let prevHour = currentHourPos
        let prevMinute = currentMinutePos
        moveHand(motor: 0, to: 0)
        moveHand(motor: 1, to: 0)
        let travel = max(estimatedTravelTime(from: 0, to: abs(prevHour)),
                         estimatedTravelTime(from: 0, to: abs(prevMinute)))
        DispatchQueue.main.asyncAfter(deadline: .now() + travel + 0.3) { [weak self] in
            guard let self else { return }
            self.bleManager?.sendCommand(name: "recalibrate", value: false)
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
            let prevHour = self.currentHourPos
            self.moveHand(motor: 0, to: counterIndex * 5)
            let travel = self.estimatedTravelTime(from: prevHour, to: counterIndex * 5)
            DispatchQueue.main.asyncAfter(deadline: .now() + travel + 0.3) { [weak self] in
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

    /// 바늘을 현재 위치에서 +delta 분 마크 만큼 시계방향으로 누적 이동 (mod 60).
    /// `moveHand`의 절대 target 모드는 wrap 시 음수 delta를 보내 반시계 회전이 되므로,
    /// 누적 모델용으로 별도 헬퍼 — 항상 양수 delta를 송신.
    private func moveHandRelative(motor: Int, byMarks delta: Int) {
        guard delta != 0 else { return }
        let scale = motor == 0 ? Self.stepsPerMinuteMarkHour : Self.stepsPerMinuteMarkMinute
        let stepDelta = delta * scale
        bleManager?.sendCommand(name: "recalibrate_move", value: [motor, stepDelta])
        let current = motor == 0 ? currentHourPos : currentMinutePos
        let next = ((current + delta) % 60 + 60) % 60
        if motor == 0 { currentHourPos = next } else { currentMinutePos = next }
    }

    /// 인식 실패 시 분침 5↔10 짧은 흔들기 후 0으로 복귀.
    private func shakeForError() {
        guard isRecalibrateActive else { return }
        moveHand(motor: 1, to: 5)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.moveHand(motor: 1, to: 10)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.moveHand(motor: 1, to: 0)
            }
        }
    }

    // MARK: - Hand Movement

    private func moveHands(to position: Int) {
        bleManager?.sendCommand(name: "stepper_goto", value: [0, position])
        bleManager?.sendCommand(name: "stepper_goto", value: [1, position])
    }

    /// 두 바늘 이동 후 시계가 수신 확인하면 콜백 호출
    private func moveHandsAndWait(hour: Int, minute: Int, onAcknowledged: @escaping () -> Void) {
        bleManager?.sendCommand(name: "stepper_goto", value: [0, hour])
        bleManager?.sendCommand(name: "stepper_goto", value: [1, minute], onComplete: onAcknowledged)
    }

    /// 바늘 이동에 필요한 예상 시간 (위치 간 거리 기반, 최소 1초)
    private func estimatedTravelTime(from: Int, to: Int) -> Double {
        let distance = abs(to - from)
        return max(1.0, Double(distance) * 0.06)
    }

    // MARK: - Random Dice

    private var isDiceRolling = false

    /// 다이얼 위치 스케일 (0–59) 기준 시(hour) 마크 위치.
    /// face 1=5, face 2=10, ... face 11=55, face 12=0.
    private func hourMarkPosition(_ face: Int) -> Int {
        (face * 5) % 60
    }

    /// 버튼 직접 매핑 경로 — recalibrate 진입부터 시작.
    /// 시작 위치 불명(현재 시각 어디든) → 보수적으로 30 스텝 거리 가정.
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
        // recalibrate(true) → 진입 시 펌웨어가 바늘을 0으로 이동.
        bleManager?.sendCommand(name: "recalibrate", value: true)
        // 명시적 stepper_goto(0) 보강 — 재진입 포함 어떤 상태에서도 12시로 확정.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.bleManager?.sendCommand(name: "stepper_goto", value: [0, 0])
            self?.bleManager?.sendCommand(name: "stepper_goto", value: [1, 0])
        }
        // 시작 위치 보수적 추정: 30 스텝 * 0.06 = 1.8s → 2초
        startDiceRoll(travelToZero: 2.0, max: max)
    }

    /// 확장입력모드 경로 — recalibrate 이미 활성, 바늘이 value 위치에 있음.
    private func rollDiceInRecalibrate(max: Int, fromPosition: Int) {
        guard !isDiceRolling else {
            bleManager?.log("주사위 중복 실행 무시")
            return
        }
        isDiceRolling = true
        // 이미 recalibrate 모드 — 재발행만으론 바늘이 이동 안 함. 명시적 stepper_goto(0) 필요.
        bleManager?.sendCommand(name: "stepper_goto", value: [0, 0])
        bleManager?.sendCommand(name: "stepper_goto", value: [1, 0])
        let travel = estimatedTravelTime(from: fromPosition, to: 0)
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
                // 분침(motor 1)만 이동 — 시침은 인트로에서 12시로 정렬된 상태 유지
                self?.bleManager?.sendCommand(name: "stepper_goto", value: [1, position])
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

    /// 확장입력모드에서 호출 — recalibrate 유지한 채 바로 이동
    private func executeDisplayAction(_ action: ButtonAction, fromPosition: Int) {
        let (hourPos, minutePos) = displayPositions(for: action)
        displayLogMessage(for: action, hourPos: hourPos, minutePos: minutePos)

        moveHandsAndWait(hour: hourPos, minute: minutePos) { [weak self] in
            guard let self else { return }
            let maxDistance = max(abs(hourPos - fromPosition), abs(minutePos - fromPosition))
            let travelTime = self.estimatedTravelTime(from: 0, to: maxDistance)

            DispatchQueue.main.asyncAfter(deadline: .now() + travelTime + 3.0) { [weak self] in
                self?.exitRecalibrateAndSyncTime()
            }
        }
    }

    /// 직접 버튼에서 호출 — recalibrate 진입부터 시작
    private func showDateOnWatch() { showDisplayOnWatch(.showDate) }
    private func showBatteryOnWatch() { showDisplayOnWatch(.showBattery) }
    private func showStepsOnWatch() { showDisplayOnWatch(.showSteps) }

    private func showDisplayOnWatch(_ type: ButtonActionType) {
        let action = ButtonAction(type: type)
        let (hourPos, minutePos) = displayPositions(for: action)

        // recalibrate(true) → 시계 수신 확인 후 0시 이동 대기 → stepper_goto
        bleManager?.sendCommand(name: "recalibrate", value: true, onComplete: { [weak self] in
            guard let self else { return }
            // 펌웨어가 0시로 이동하는 시간 대기
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self else { return }
                self.displayLogMessage(for: action, hourPos: hourPos, minutePos: minutePos)

                self.moveHandsAndWait(hour: hourPos, minute: minutePos) { [weak self] in
                    guard let self else { return }
                    let maxPos = max(hourPos, minutePos)
                    let travelTime = self.estimatedTravelTime(from: 0, to: maxPos)

                    DispatchQueue.main.asyncAfter(deadline: .now() + travelTime + 3.0) { [weak self] in
                        self?.exitRecalibrateAndSyncTime()
                    }
                }
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
    }

    func saveMorse() {
        if let data = try? JSONEncoder().encode(morseMappings) {
            UserDefaults.standard.set(data, forKey: Self.morseKey)
        }
    }
}