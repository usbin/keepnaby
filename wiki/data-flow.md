<!-- 최종 수정: 2026-05-18 -->

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
  ├─ 표시(날짜·배터리·걸음수)·주사위 → 핸드 세션 락 (한 번에 하나)
  │    └─ begin: alert_assign([0,0,0]) 억제 → recalibrate(true) → 바늘 구동
  │       end: recalibrate(false) → datetime → alert_assign 원복
  ├─ MusicController (재생·일시정지·다음·이전)
  ├─ LocationRecorder.capture()
  │    └─ CLLocationManager → 역지오코딩 → 저장
  ├─ FindMyPhone.trigger()
  ├─ MorseDecoder 모드 진입
  ├─ WaterIntakeManager.recordDrink()
  │    └─ standardAmountML 만큼 추가 + 진동 1회 피드백
  └─ 커스텀 URL Webhook
```

---

## ANCS 알림 흐름

ANCS 는 iPhone↔워치 사이의 **별도 GATT 연결** — 워치 펌웨어가 iOS 의 ANCS 서비스(`7905F431...`)에 client 로 직접 구독한다. Keepnaby 앱은 그 채널을 직접 관찰하지 못하고, 워치 펌웨어에 `ancs_filter` 명령으로 필터 슬롯만 설정한다.

```
iOS 알림 발생 → iPhone ANCS 서비스 → 워치 펌웨어가 직접 수신
                                       │ (앱 미경유)
                                       ▼
                              펌웨어가 ancs_filter 슬롯과 매칭
                                       │
                                       ▼
                              매칭된 슬롯 (1·2·3) 진동 + 바늘 이동 실행
```

알림→바늘 이동은 펌웨어 동작이며 `alert_assign`으로만 게이트된다(앱이 직접 못 막음). 표시/주사위 핸드 세션 동안 `ButtonActionManager`가 `alert_assign([0,0,0])`로 잠시 끄고 종료 시 마지막 값(`UserDefaults["kronaby_last_alert_assign"]`, 없으면 [0,0,0])으로 원복 — 세션 중 펌웨어가 바늘을 옮겨 영점이 깨지는 것을 차단(자세한 분석은 `devnotes.md`).

ANCS 끊김 자동 복구 (range loss → 재연결 시점에 자동 escalation, `BLEManager`):

```
didDisconnectPeripheral (signal lost)
  │  disconnectTimestamp = now
  ▼
... (out of range) ...
  │
  ▼
didConnect (back in range) + characteristic 재발견 완료
  │  elapsed = now - disconnectTimestamp
  ▼
elapsed ≥ 60s   → Tier 2 자동 (NotificationMappingManager.applyToWatch — ancs_filter 35슬롯 재전송)
elapsed ≥ 1h    → Tier 2 + 10초 후 Tier 3 (CBCentralManager 재생성, BT off/on 흉내)
```

수동 복구 버튼은 메뉴에 Tier 1/2/3 분리해 노출 — 효과 검증용.

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
