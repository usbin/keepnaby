import CoreBluetooth
import Combine
import UserNotifications

enum ConnectionState: String {
    case disconnected = "연결 끊김"
    case scanning = "스캔 중..."
    case connecting = "연결 중..."
    case handshaking = "핸드셰이크 중..."
    case connected = "연결됨"
    case bluetoothOff = "블루투스 꺼짐"
}

final class BLEManager: NSObject, ObservableObject {
    @Published var connectionState: ConnectionState = .disconnected
    @Published var discoveredPeripherals: [CBPeripheral] = []
    @Published var commandMap: [String: Int] = [:]
    @Published var lastButtonEvent: ButtonEvent?
    @Published var batteryInfo: [Int]?  // [percentage, millivolts]
    @Published var stepsInfo: [Int]?   // [steps, dayOfMonth] from steps_day
    @Published var debugLog: [String] = []
    @Published var settingsMap: [Int: String] = [:]  // map_settings 결과: {id: "name"}

    private var centralManager: CBCentralManager!
    private(set) var peripheral: CBPeripheral?
    private(set) var commandChar: CBCharacteristic?
    private var notifyChar: CBCharacteristic?

    private let protocol_ = KronabyProtocol()
    private var pendingScan = false
    private var handshakeStep = 0
    private var handshakeResponseCount = 0
    private var lastReadHex = ""
    private var readRetryCount = 0
    private var serviceDiscoveryRetryCount = 0

    // map_settings 페이지 읽기 상태
    private var isReadingSettingsMap = false
    private var settingsMapPage = 0
    private var pendingSettingsRead = false

    private static let savedPeripheralKey = "kronaby_peripheral_uuid"
    private static let savedCommandMapKey = "kronaby_command_map"

    private func savePeripheralID(_ uuid: UUID) {
        UserDefaults.standard.set(uuid.uuidString, forKey: Self.savedPeripheralKey)
    }

    private func loadSavedPeripheralID() -> UUID? {
        guard let str = UserDefaults.standard.string(forKey: Self.savedPeripheralKey) else { return nil }
        return UUID(uuidString: str)
    }

    private func saveCommandMap() {
        UserDefaults.standard.set(commandMap, forKey: Self.savedCommandMapKey)
        log("commandMap 저장 (\(commandMap.count)개)")
    }

    private func loadSavedCommandMap() -> [String: Int]? {
        return UserDefaults.standard.dictionary(forKey: Self.savedCommandMapKey) as? [String: Int]
    }

    static let restoreIdentifier = "com.usbin.kronaby.ble"

    override init() {
        super.init()
        centralManager = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [CBCentralManagerOptionRestoreIdentifierKey: Self.restoreIdentifier]
        )
        log("BLEManager 초기화 (State Restoration)")
    }

    func log(_ msg: String) {
        let time = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        debugLog.append("[\(time)] \(msg)")
        // Keep last 50 entries
        if debugLog.count > 500 { debugLog.removeFirst() }
    }

    // MARK: - Public API

    func startScan() {
        log("startScan() — BLE state: \(centralManager.state.rawValue)")
        guard centralManager.state == .poweredOn else {
            pendingScan = true
            if centralManager.state == .poweredOff {
                connectionState = .bluetoothOff
            }
            log("BLE not ready, queued scan")
            return
        }
        pendingScan = false
        discoveredPeripherals = []
        connectionState = .scanning

        // F431 서비스 UUID로 필터 — 페어링 모드 시계만 검색
        centralManager.scanForPeripherals(
            withServices: [BLEConstants.kronabyAdvertisementUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        log("스캔 시작됨 (F431 필터)")

        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self, self.connectionState == .scanning else { return }
            self.log("스캔 30초 타임아웃")
            self.stopScan()
        }
    }

    func stopScan() {
        centralManager.stopScan()
        if connectionState == .scanning {
            connectionState = .disconnected
        }
        log("스캔 중지")
    }

    func connect(to peripheral: CBPeripheral) {
        stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        connectionState = .connecting
        log("연결 시도: \(peripheral.name ?? "unknown") (\(peripheral.identifier))")
        centralManager.connect(peripheral, options: nil)

        // 30초 연결 타임아웃
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self, self.connectionState == .connecting else { return }
            self.log("연결 타임아웃 — 실패")
            self.disconnect()
        }
    }

    private var intentionalDisconnect = false
    private var disconnectTimestamp: Date?
    var onConnected: (() -> Void)?

    /// 장시간 끊김 임계값 — 이보다 오래 끊겼다 재연결되면 ANCS 재구독 유도 목적으로 강제 full reconnect 수행
    private static let longDisconnectThreshold: TimeInterval = 5 * 60

    func disconnect() {
        intentionalDisconnect = true
        if let peripheral = peripheral {
            centralManager.cancelPeripheralConnection(peripheral)
            log("연결 해제 요청")
        }
    }

    /// 수동/자동 ANCS 복구용 — 페리퍼럴 연결을 완전히 끊고 자동 재연결을 유도.
    /// Bluetooth off/on 을 앱 레벨에서 흉내낸 것. 워치 쪽에서 GATT 재협상이 일어나며
    /// ANCS 서비스 구독도 다시 이루어질 가능성이 높음.
    func forceFullReconnect() {
        guard let peripheral = peripheral else {
            log("forceFullReconnect: peripheral 없음")
            return
        }
        log("강제 재연결 시작 (ANCS 복구 시도)")
        // intentionalDisconnect 는 false 로 유지 → didDisconnect 핸들러가 자동 재연결
        // disconnectTimestamp 가 직후 재설정되지만 gap 이 짧아 재재연결은 트리거되지 않음
        centralManager.cancelPeripheralConnection(peripheral)
    }

    func forgetDevice() {
        disconnect()
        UserDefaults.standard.removeObject(forKey: Self.savedPeripheralKey)
        UserDefaults.standard.removeObject(forKey: Self.savedCommandMapKey)
        commandMap.removeAll()
        log("저장된 기기 정보 삭제")
    }

    private func sendDisconnectNotification() {
        // 5초 후 발송 — 그 사이에 재연결되면 취소됨
        let content = UNMutableNotificationContent()
        content.title = "Keepnaby 연결 끊김"
        content.body = "시계와의 연결이 끊겼습니다. 재연결을 시도합니다."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let request = UNNotificationRequest(identifier: "ble_disconnect", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    private func cancelDisconnectNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["ble_disconnect"])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["ble_disconnect"])
    }

    /// 백그라운드에서 깨어났을 때 호출 — GATT keepalive (설정 재전송 없음)
    func performBackgroundSync() {
        guard connectionState == .connected else {
            log("백그라운드 sync 스킵 — 미연결")
            return
        }
        log("백그라운드 keepalive (vbat 조회)")
        sendCommand(name: "vbat", value: 0)
        BackgroundSyncScheduler.shared.scheduleAppRefresh()
    }

    /// periodic 명령 (cmd 38) 탐색용 — 시계에 주기적 heartbeat 설정 시도
    func tryPeriodicCommand() {
        guard connectionState == .connected, commandMap["periodic"] != nil else { return }
        // 1시간(3600초) 간격으로 시계가 주기적 데이터를 보내도록 시도
        sendCommand(name: "periodic", value: 3600)
        log("periodic(3600) 전송 — 시계 응답 관찰 필요")
    }

    func requestBattery() {
        sendCommand(name: "vbat", value: 0)
    }

    func confirmVibration() {
        sendCommand(name: "vibrator_start", value: [150])
    }

    func requestSteps() {
        sendCommand(name: "steps_now", value: 0)
    }

    /// map_settings 읽기 시작 — 시계 펌웨어의 settings 키 매핑을 조회
    func readSettingsMap() {
        guard connectionState == .connected else {
            log("map_settings 읽기 실패: 연결 안 됨")
            return
        }
        guard commandMap["map_settings"] != nil else {
            log("map_settings 읽기 실패: commandMap에 map_settings 없음")
            return
        }
        settingsMap.removeAll()
        settingsMapPage = 0
        isReadingSettingsMap = true
        sendSettingsMapPage()
    }

    private func sendSettingsMapPage() {
        guard let char = commandChar,
              let cmdId = commandMap["map_settings"] else { return }
        let data = protocol_.encode(commandId: cmdId, value: settingsMapPage)
        let hex = data.map { String(format: "%02X", $0) }.joined()
        log("map_settings(\(settingsMapPage)) → \(hex)")
        pendingSettingsRead = true
        peripheral?.writeValue(data, for: char, type: .withResponse)
    }

    private var writeCompletionHandler: (() -> Void)?

    func sendCommand(name: String, value: Any, onComplete: (() -> Void)? = nil) {
        guard let char = commandChar,
              let cmdId = commandMap[name] else {
            log("sendCommand 실패: \(name) (char=\(commandChar != nil), map=\(commandMap[name] as Any))")
            return
        }
        let data = protocol_.encode(commandId: cmdId, value: value)
        let hex = data.map { String(format: "%02X", $0) }.joined()
        log("CMD: \(name)(\(cmdId)) → \(hex)")
        if onComplete != nil { writeCompletionHandler = onComplete }
        peripheral?.writeValue(data, for: char, type: .withResponse)
    }

    func sendRawCommand(name: String, data payload: Data) {
        guard let char = commandChar,
              let cmdId = commandMap[name] else {
            log("sendRawCommand 실패: \(name)")
            return
        }
        // {cmdId: binary_data} — MsgPack map with bin value
        let cmdData = protocol_.encodeBinary(commandId: cmdId, payload: payload)
        let hex = cmdData.prefix(20).map { String(format: "%02X", $0) }.joined()
        log("CMD(raw): \(name)(\(cmdId)) → \(hex)... (\(cmdData.count)B)")
        peripheral?.writeValue(cmdData, for: char, type: .withResponse)
    }

    // MARK: - Connection Sequence

    private func performHandshake() {
        connectionState = .handshaking
        handshakeStep = 0
        handshakeResponseCount = 0
        lastReadHex = ""
        readRetryCount = 0
        commandMap.removeAll()
        log("핸드셰이크 시작")
        sendNextHandshakeStep()
    }

    private var pendingHandshakeRead = false

    private func sendNextHandshakeStep() {
        guard handshakeStep <= 2 else {
            log("핸드셰이크 3단계 전송 완료")
            return
        }
        guard let char = commandChar else {
            log("핸드셰이크 실패: commandChar 없음")
            return
        }
        let step = handshakeStep
        let data = protocol_.encodeArray([0, step])
        pendingHandshakeRead = true
        // withResponse로 전송 — didWriteValueFor 콜백에서 read
        peripheral?.writeValue(data, for: char, type: .withResponse)
        log("map_cmd(\(step)) → \(data.map { String(format: "%02X", $0) }.joined())")
    }

    private func completeSetup() {
        log("핸드셰이크 완료 — commandMap \(commandMap.count)개")

        // 검증: commandMap에 필수 키가 있어야 함
        guard commandMap.count >= 10,
              commandMap["onboarding_done"] != nil,
              commandMap["datetime"] != nil else {
            log("핸드셰이크 실패 — commandMap 불완전 (\(commandMap.count)개)")
            disconnect()
            return
        }

        saveCommandMap()
        disconnectTimestamp = nil
        connectionState = .connected
        // 핸드셰이크 write/read 완료 후 충분히 대기 → onboarding_done 전송
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            self.sendCommand(name: "onboarding_done", value: 1)
            // 만보기 활성화
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.sendCommand(name: "config_base", value: [1, 1])
            }
            self.log("연결됨! 영점 조정 → 시각 설정 순서로 진행하세요.")
            BackgroundSyncScheduler.shared.scheduleAppRefresh()
            self.onConnected?()
        }
    }

    // MARK: - Filtering

    // F431 서비스 필터로 스캔하므로 didDiscover에 오는 건 모두 Kronaby 시계
}

// MARK: - CBCentralManagerDelegate

extension BLEManager: CBCentralManagerDelegate {
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        log("State Restoration 시작")
        // iOS가 앱을 깨웠을 때 이전 연결 복원
        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral],
           let restored = peripherals.first {
            log("복원된 페리퍼럴: \(restored.name ?? "?")")
            self.peripheral = restored
            restored.delegate = self

            if restored.state == .connected {
                log("이미 연결됨 — 서비스 재검색")
                connectionState = .connecting
                restored.discoverServices(nil)
            } else {
                log("복원 후 재연결 시도")
                connectionState = .connecting
                central.connect(restored, options: nil)
            }
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        log("BLE state → \(central.state.rawValue)")
        switch central.state {
        case .poweredOn:
            // 저장된 페리퍼럴이 이미 연결 상태인 경우만 복원
            if let savedID = loadSavedPeripheralID(),
               let device = central.retrievePeripherals(withIdentifiers: [savedID]).first {
                if device.state == .connected {
                    log("기존 연결 복원: \(device.name ?? "?")")
                    self.peripheral = device
                    device.delegate = self
                    connectionState = .connecting
                    device.discoverServices(nil)
                    return
                } else if loadSavedCommandMap() != nil {
                    log("저장된 기기 재연결 시도: \(device.name ?? "?")")
                    self.peripheral = device
                    device.delegate = self
                    connectionState = .connecting
                    central.connect(device, options: nil)
                    return
                }
                log("저장된 기기 미연결 — 스캔 필요")
            }
            if pendingScan { startScan() }
        case .poweredOff:
            connectionState = .bluetoothOff
        default:
            connectionState = .disconnected
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        // F431 서비스 필터로 이미 페어링 모드 시계만 들어옴
        log("발견: \(peripheral.name ?? "?") RSSI:\(RSSI)")
        if !discoveredPeripherals.contains(where: { $0.identifier == peripheral.identifier }) {
            discoveredPeripherals = discoveredPeripherals + [peripheral]
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        log("BLE 연결됨 — 서비스 검색 시작")
        cancelDisconnectNotification()
        serviceDiscoveryRetryCount = 0
        savePeripheralID(peripheral.identifier)
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        log("연결 실패: \(error?.localizedDescription ?? "unknown")")
        connectionState = .disconnected
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        log("연결 끊김: \(error?.localizedDescription ?? "정상")")
        commandChar = nil
        notifyChar = nil
        // BGTask는 iOS가 관리하므로 별도 정리 불필요

        if !intentionalDisconnect, loadSavedCommandMap() != nil {
            // 의도치 않은 끊김 → 자동 재연결 + 알림
            // 끊김 시각 기록 — 재연결 후 장시간 여부 판단에 사용
            if disconnectTimestamp == nil {
                disconnectTimestamp = Date()
            }
            log("자동 재연결 시도...")
            connectionState = .connecting
            central.connect(peripheral, options: nil)
            sendDisconnectNotification()
        } else {
            // 유저가 요청한 연결 해제
            intentionalDisconnect = false
            disconnectTimestamp = nil
            connectionState = .disconnected
            self.peripheral = nil
            commandMap.removeAll()
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            log("서비스 검색 에러: \(error.localizedDescription)")
            retryServiceDiscovery(peripheral)
            return
        }
        guard let services = peripheral.services, !services.isEmpty else {
            log("서비스 없음")
            retryServiceDiscovery(peripheral)
            return
        }
        serviceDiscoveryRetryCount = 0
        log("서비스 발견: \(services.map { $0.uuid.uuidString })")
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    /// 서비스 검색 실패 시 재시도 (최대 3회, 2초 간격)
    private func retryServiceDiscovery(_ peripheral: CBPeripheral) {
        serviceDiscoveryRetryCount += 1
        guard serviceDiscoveryRetryCount <= 3 else {
            log("서비스 검색 재시도 \(serviceDiscoveryRetryCount - 1)회 실패 — 포기")
            serviceDiscoveryRetryCount = 0
            return
        }
        log("서비스 검색 재시도 \(serviceDiscoveryRetryCount)/3 — 2초 후")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let _ = self, peripheral.state == .connected else { return }
            peripheral.discoverServices(nil)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            log("특성 검색 에러 (\(service.uuid)): \(error.localizedDescription)")
            return
        }
        guard let chars = service.characteristics else { return }
        log("특성 [\(service.uuid)]: \(chars.map { $0.uuid.uuidString })")

        for char in chars {
            switch char.uuid {
            case BLEConstants.commandCharUUID:
                commandChar = char
                peripheral.setNotifyValue(true, for: char)
                log("→ commandChar 획득")
            case BLEConstants.notifyCharUUID:
                notifyChar = char
                peripheral.setNotifyValue(true, for: char)
                log("→ notifyChar 획득")
            default:
                break
            }
        }

        if commandChar != nil && notifyChar != nil && connectionState == .connecting {
            // 저장된 commandMap이 있으면 핸드셰이크 스킵
            if let savedMap = loadSavedCommandMap(), !savedMap.isEmpty {
                commandMap = savedMap
                log("저장된 commandMap 복원 (\(savedMap.count)개)")
                connectionState = .connected

                // 장시간 끊김 후 재연결이면 ANCS 구독이 끊겼을 가능성이 높음 →
                // 짧은 지연 후 강제 full reconnect 수행 (Bluetooth off/on 재현)
                let shouldRefreshAncs: Bool = {
                    guard let t = disconnectTimestamp else { return false }
                    return Date().timeIntervalSince(t) >= Self.longDisconnectThreshold
                }()
                disconnectTimestamp = nil

                // 초기 페어링과 동일하게 지연 후 명령 전송 — 펌웨어 안정화 대기
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    guard let self, self.connectionState == .connected else { return }
                    self.sendCommand(name: "onboarding_done", value: 1)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        self?.sendCommand(name: "config_base", value: [1, 1])
                    }
                    self.log("재연결 완료!")
                    BackgroundSyncScheduler.shared.scheduleAppRefresh()
                    self.onConnected?()

                    // 장시간 끊김 후 재연결 → 2초 뒤 ANCS 복구용 강제 재연결
                    if shouldRefreshAncs {
                        self.log("장시간 끊김 감지 → 2초 후 ANCS 복구 재연결 예약")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                            self?.forceFullReconnect()
                        }
                    }
                }
            } else {
                performHandshake()
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        log("Notify 상태 변경 [\(characteristic.uuid)]: isNotifying=\(characteristic.isNotifying), error=\(error?.localizedDescription ?? "없음")")
        if !characteristic.isNotifying && error == nil {
            log("⚠️ Notify 구독 해제됨 — 재구독 시도")
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        log("서비스 변경 감지: \(invalidatedServices.map { $0.uuid.uuidString })")
        // GATT 테이블이 변경되면 특성이 무효화됨 — 서비스 재검색
        commandChar = nil
        notifyChar = nil
        peripheral.discoverServices(nil)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            log("쓰기 에러 [\(characteristic.uuid)]: \(error.localizedDescription)")
        } else {
            log("쓰기 성공 [\(characteristic.uuid)]")
            // 핸드셰이크 중 write 성공 → read로 응답 받기
            if pendingHandshakeRead && characteristic.uuid == BLEConstants.commandCharUUID {
                pendingHandshakeRead = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self, let p = self.peripheral, let c = self.commandChar else { return }
                    p.readValue(for: c)
                    self.log("map_cmd(\(self.handshakeStep)) read 요청")
                }
            }
            // map_settings write 성공 → read로 응답 받기
            if pendingSettingsRead && characteristic.uuid == BLEConstants.commandCharUUID {
                pendingSettingsRead = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self, let p = self.peripheral, let c = self.commandChar else { return }
                    p.readValue(for: c)
                    self.log("map_settings(\(self.settingsMapPage)) read 요청")
                }
            }
            // 쓰기 완료 콜백
            if let handler = writeCompletionHandler {
                writeCompletionHandler = nil
                DispatchQueue.main.async { handler() }
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            log("값 수신 에러: \(error.localizedDescription)")
            return
        }
        guard let data = characteristic.value else { return }
        let hex = data.map { String(format: "%02X", $0) }.joined()
        log("수신 [\(characteristic.uuid)]: \(hex)")

        let decoded = protocol_.decode(data: data)

        if connectionState == .handshaking {
            let isFromCommandChar = characteristic.uuid == BLEConstants.commandCharUUID
            var foundMap = false

            // Case 1: response is directly {string: int}
            if let map = decoded as? [String: Int] {
                commandMap.merge(map) { _, new in new }
                log("맵(직접): \(commandMap.count)개")
                foundMap = true
            }
            // Case 2: response is {int: {string: int}} — wrapped
            else if let outer = decoded as? [Int: Any] {
                for (key, value) in outer {
                    // {0: {string_name: int_id}} — name→id
                    if let innerMap = value as? [String: Int] {
                        commandMap.merge(innerMap) { _, new in new }
                        log("맵(name→id key=\(key)): \(commandMap.count)개")
                        foundMap = true
                    }
                    // {0: {int_id: string_name}} — id→name (실제 형식)
                    else if let innerMap = value as? [Int: Any] {
                        for (id, name) in innerMap {
                            if let nameStr = name as? String {
                                commandMap[nameStr] = id
                            }
                        }
                        if !innerMap.isEmpty {
                            log("맵(id→name key=\(key)): \(commandMap.count)개")
                            foundMap = true
                        }
                    }
                }
            }

            if !foundMap {
                log("응답(맵 아님) [\(isFromCommandChar ? "cmd" : "ntf")]: \(String(describing: decoded))")
            }

            // command 특성에서 read 응답이 온 경우 → 다음 step 진행
            if isFromCommandChar {
                // 이전과 같은 데이터면 write 재전송 (최대 10회)
                if hex == lastReadHex && handshakeStep > 0 {
                    readRetryCount += 1
                    if readRetryCount > 10 {
                        log("핸드셰이크 실패 — step \(handshakeStep) 응답 없음")
                        disconnect()
                        return
                    }
                    log("같은 데이터 — \(readRetryCount)회 재시도")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                        guard let self, self.connectionState == .handshaking else { return }
                        self.sendNextHandshakeStep()
                    }
                    return
                }
                lastReadHex = hex
                readRetryCount = 0
                handshakeStep += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self, self.connectionState == .handshaking else { return }
                    if self.handshakeStep <= 2 {
                        self.sendNextHandshakeStep()
                    } else {
                        self.log("핸드셰이크 완료 — commandMap \(self.commandMap.count)개")
                        self.completeSetup()
                    }
                }
            }
        } else if connectionState == .connected {
            // map_settings 응답 처리
            if isReadingSettingsMap {
                var pageMap: [Int: String] = [:]
                if let dict = decoded as? [Int: Any] {
                    // {35: {id: "name", ...}} 또는 {35: null} 형식
                    let settingsId = commandMap["map_settings"] ?? -1
                    if let inner = dict[settingsId] as? [Int: String] {
                        pageMap = inner
                    } else if let inner = dict[settingsId] as? [Int: Any] {
                        for (k, v) in inner {
                            if let name = v as? String { pageMap[k] = name }
                        }
                    }
                    // 직접 {id: "name"} 형식
                    if pageMap.isEmpty {
                        for (k, v) in dict {
                            if let name = v as? String { pageMap[k] = name }
                        }
                    }
                }

                if pageMap.isEmpty {
                    // 빈 페이지 → 읽기 완료
                    isReadingSettingsMap = false
                    log("map_settings 완료 — \(settingsMap.count)개 키:")
                    for key in settingsMap.keys.sorted() {
                        log("  \(key): \(settingsMap[key] ?? "?")")
                    }
                } else {
                    settingsMap.merge(pageMap) { _, new in new }
                    log("map_settings 페이지 \(settingsMapPage): \(pageMap.count)개 (누적 \(settingsMap.count)개)")
                    // 다음 페이지 요청
                    settingsMapPage += 1
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        self?.sendSettingsMapPage()
                    }
                }
                return
            }
            if let event = protocol_.parseButtonEvent(decoded, commandMap: commandMap) {
                lastButtonEvent = event
                log("버튼: \(event.buttonName) \(event.eventName)")
            } else if let dict = decoded as? [Int: Any],
                      let vbatId = commandMap["vbat"],
                      let mv = dict[vbatId] as? Int {
                // millivolts → percentage (CR2025: 3000mV=100%, 2000mV=0%)
                let percent = min(100, max(0, (mv - 2000) * 100 / 1000))
                batteryInfo = [percent, mv]
                log("배터리: \(mv)mV → \(percent)%")
            } else if let dict = decoded as? [Int: Any],
                      let stepsId = commandMap["steps_now"] {
                // steps_now: 단일 int 또는 [steps, day] 배열
                if let arr = dict[stepsId] as? [Any],
                   arr.count >= 2,
                   let steps = arr[0] as? Int,
                   let day = arr[1] as? Int {
                    stepsInfo = [steps, day]
                    log("걸음수: \(steps)보 (day \(day))")
                } else if let steps = dict[stepsId] as? Int {
                    stepsInfo = [steps, 0]
                    log("걸음수: \(steps)보")
                }
            } else if let dict = decoded as? [Int: Any],
                      let stepsId = commandMap["steps_day"],
                      let arr = dict[stepsId] as? [Any],
                      arr.count >= 2,
                      let steps = arr[0] as? Int,
                      let day = arr[1] as? Int {
                stepsInfo = [steps, day]
                log("걸음수(일별): \(steps)보 (day \(day))")
            } else {
                log("수신(연결): \(String(describing: decoded))")
            }
        }
    }
}
