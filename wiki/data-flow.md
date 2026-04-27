<!-- 최종 수정: 2026-04-27 -->

# 데이터 흐름

## BLE 연결 흐름

```
앱 실행
  │
  ▼
BLEManager.startScanning()
  │  CBCentralManager 상태 확인
  ▼
기기 발견 (CBPeripheral)
  │
  ▼
connect(peripheral)
  │
  ▼
서비스·캐릭터리스틱 탐색
  │
  ▼
핸드셰이크 (map_cmd 폴 3회)
  │  920000 → 920001 → 920002
  │  → 지원 명령 74개 목록 수신
  ▼
connected 상태
  │
  ├─ 배터리·걸음 수 주기 폴링
  ├─ ANCS 알림 수신 대기
  └─ 버튼 이벤트 수신 대기 (Notify 캐릭터리스틱)
```

---

## BLE 명령 파이프라인 (앱 → 워치)

```
UI 액션 또는 Features 매니저
  │
  ▼
KronabyProtocol.encode(command, value)
  │  Map { commandId: Int => value } 형태
  ▼
MiniMsgPack.encode()
  │  MessagePack 바이너리 직렬화
  ▼
BLEManager.writeCharacteristic()
  │  Write Without Response
  ▼
Kronaby 워치 펌웨어 처리
```

---

## 버튼 이벤트 파이프라인 (워치 → 앱)

```
워치 버튼 물리 입력
  │
  ▼
BLE Notify 캐릭터리스틱 → BLEManager 수신
  │  MiniMsgPack 디코딩
  ▼
ButtonEvent { button: Int, eventType: Int }
  │
  ▼
ButtonActionManager.handleEvent(event)
  │  10가지 조합 매핑 조회 (UserDefaults)
  ▼
매핑된 액션 실행
  ├─ MusicController (재생·일시정지·다음·이전)
  ├─ LocationRecorder.capture()
  │    └─ CLLocationManager → 역지오코딩 → 저장
  ├─ FindMyPhone.trigger()
  ├─ MorseDecoder 모드 진입
  └─ 커스텀 URL Webhook
```

---

## ANCS 알림 흐름

```
iOS 알림 발생 (카카오톡, 전화 등)
  │
  ▼
CoreBluetooth ANCS 서비스 → BLEManager 수신
  │  앱 번들 ID 포함
  ▼
NotificationMappingManager.filter(bundleId)
  │  UserDefaults 매핑 조회 → 진동 슬롯(1·2·3) 결정
  ▼
KronabyProtocol.vibrate(slot)
  │
  ▼
워치 진동 패턴 실행
```

---

## 백그라운드 동기화

```
BGTaskScheduler (ID: com.usbin.kronaby.sync)
  │  앱 백그라운드 전환 시 태스크 등록
  ▼
BackgroundSyncScheduler.handleSync()
  │
  ▼
BLEManager 재연결 시도 (State Restoration)
  │
  ▼
시간·날짜 자동 동기화 명령 전송
```

---

## 외부 서비스 연동

| 서비스 | 연동 지점 | 방향 |
|--------|-----------|------|
| HealthKit | `LocationRecorder` (걸음 수 읽기) | 읽기 |
| CLLocationManager | `LocationRecorder` | 읽기 |
| 지도 URL 스킴 (카카오·네이버·구글) | `LocationRecorder` | 앱 열기 |
| ANCS | `BLEManager` via CoreBluetooth | 읽기 |
