<!-- 최종 수정: 2026-07-14 -->

# 개발 노트

## 알려진 이슈

### 배터리 표시가 항상 12시 후 복귀 (2026-07-14 해결, v1.1.9)
- **증상**: 배터리 확인 명령 시 시침·분침 모두 12시를 잠깐 가리키다 현재시각으로 복귀. 실제 잔량을 안 보여줌.
- **원인**: 배터리 표시 경로(`showDisplayOnWatch`·모스 `runMorseExecution` → `executeDisplayAction` → `displayPositions`)가 `requestBattery()`(vbat) 없이 `bleManager.batteryInfo`를 읽음. `requestBattery`는 `ConnectionView`의 수동 메뉴에서만 호출돼, 명령 시점엔 대개 `batteryInfo == nil` → `percent = 0` → `pos = 0`(12시). 직전에 수동 조회를 안 했으면 항상 재현.
- **부수 문제**: 스케일이 `× 59.0`(0~100%를 거의 한 바퀴 0~59마크에 매핑) → 사용자 기대(100% = "10" 눈금 = 50분)와 불일치.
- **해결**: ① `BLEManager.onBatteryUpdate`(1회성 콜백) 추가 — vbat 응답으로 `batteryInfo` 갱신 시 발화. ② `ButtonActionManager.withFreshBattery(_:)` — 세션/recalibrate 진입 **이후** `requestBattery()` 보내고 콜백(또는 2초 타임아웃) 대기 후 표시. 세션 진입 뒤라 `alert_assign([0,0,0])` 억제가 이미 걸려 대기 중 ANCS가 바늘을 못 건드림(모스 경로는 recalibrate 유지 상태라 동일 보호). 직접·모스 배터리 경로 공통 적용. ③ 배터리·걸음수 스케일 `× 59.0 → × 50.0`(100% = "10" 눈금 50분, 40% = "4" 20분).
- **검증 상태**: v1.1.9 CI success(컴파일 OK). 실기 동작(잔량 위치·모스 경로 vbat이 recalibrate 유지하는지) 사용자 테스트 대기.

### ANCS 24시간 후 끊김 (해결됨)
- **증상**: BLE 연결 유지 중 24시간 이후 ANCS 알림 수신 중단
- **원인**: CoreBluetooth idle timeout 후 GATT 캐시 만료
- **해결**: 전체 GATT 재협상 로직 추가
- 상세: `docs/resolved/issue-ancs-drops-after-day.md`

### ANCS range-loss 후 끊김 — 자동 복구 (2026-05-08)
- **증상**: 시계와 휴대폰이 BLE 신호 닿는 거리에서 일정 시간 이상 떨어졌다 다시 가까워질 때 ANCS 구독이 안 살아남. BT off/on 으로만 복구되던 것.
- **2026-05-08 대응**: `BLEManager` 가 `didDisconnect` 시점부터의 경과 시간 (`disconnectTimestamp`) 을 기반으로 재연결 직후 자동 escalation:
  - 60초 이상 끊김 → Tier 2 자동 (`NotificationMappingManager.applyToWatch` — ancs_filter 35슬롯 재전송, 비용 ~3.5초 BLE)
  - 1시간 이상 끊김 → Tier 2 + 10초 뒤 Tier 3 (`CBCentralManager` 폐기·재생성 — BT off/on 흉내내는 가장 깊은 in-app 리셋)
- **수동 복구**: 메뉴에 Tier 1/2/3 분리 노출 — 재발 시 어느 tier 에서 효과 있는지 사용자가 검증 가능.
- **검증 어려움**: 앱이 ANCS 채널 자체를 관찰할 수 없음 (워치가 iPhone ANCS 서비스에 client 로 직접 구독, 앱 미경유). 따라서 자동 복구 효과는 "재발 빈도 감소" 로만 간접 측정.

### 빠른 연속 버튼 입력 시 바늘 영구 틀어짐 (2026-05-18 1차 대응)
- **증상**: 정상 모드에서 표시/주사위 액션 버튼을 빠르게 연달아 누르면(예: 상단 1회→곧바로 2회) 바늘이 12시→엉뚱한 위치→그때부터 영구히 틀어짐.
- **원인**: `ButtonActionManager`의 `showDate`/`showBattery`/`showSteps`에 재진입 가드 부재(주사위는 `isDiceRolling`만, 액션 간 보호 없음). 겹친 두 시퀀스가 ① 공유 `MotorTrack`(hour/minuteTrack) ② `BLEManager`의 단일 `writeCompletionHandler`(나중 호출이 덮어씀, `:294/:305`) ③ 시간추정 기반 `recalibrate(false)`(`exitRecalibrateAndSyncTime`, 물리 도착 미확인)를 동시에 짓밟음 → 펌웨어가 12시 아닌 위치를 영점으로 래치 → 이후 모든 시각·날짜 표시 오프셋.
- **ANCS 가설은 기각**: 앱은 알림 수신 시 바늘을 움직이지 않음(펌웨어가 ANCS 직접 구독, 앱은 `ancs_filter` 진동 슬롯만). 펌웨어 자체 알림 제스처가 recalibrate 세션 중 끼면 2차 악화는 가능하나 주범 아님.
- **1차 대응 (앱 재진입 차단)**: 정상-모드 핸드 구동 액션 전용 단일 락 `isWatchHandSessionActive`(`beginWatchHandSession`/`endWatchHandSession`). `showDisplayOnWatch`·`rollRandomDice` 진입 시 락 확인·획득(+미연결 가드 — 락 데드락 방지), `exitRecalibrateAndSyncTime`의 datetime 전송 완료 후 해제. BLE write 무응답으로 종료 콜백이 안 와도 30초 워치독이 `endWatchHandSession` 호출로 강제 해제. 모스 경로(`isMorseMode` 분기)는 락 미보유 — 영향 없음.
- **2차 대응 (펌웨어 알림 제스처 차단)**: 알림→바늘 이동은 펌웨어 동작이라 앱이 막을 유일한 레버가 `alert_assign`. 세션 진입 시 `alert_assign([0,0,0])`로 알림 제스처 억제, 종료 시 원복. 복원값은 `NotificationMappingManager.applyToWatch`/`AlarmManager.applyToWatch`가 alert_assign 전송 시마다 `UserDefaults["kronaby_last_alert_assign"]`에 영속한 마지막 값(없으면 [0,0,0] — 미설정 상태와 동일해 안전). 세션 중 사용자가 알림 설정 변경·Apply하면 키도 갱신돼 원복값이 따라감(begin 시점 캐시 아닌 end 시점 read). 비용: BLE write 2개(~50–60ms, 액션 5–10초 대비 무시 가능) + 세션(~5–10초) 중 도착 알림 진동/제스처 누락(의도된 트레이드오프 — "한 번에 한 동작" 정책과 일치).
- **알림 제스처 vs recalibrate 세션 상호작용**: recalibrate(true) 모드 중 ANCS 알림 시 펌웨어가 제스처를 발화하는지는 캡처에 없음(RE 캡처의 알림→바늘은 전부 시각모드). 펌웨어엔 표시중 임의 위치(예: 4:20) 기억이 없어 알림 후 직전 위치로 복귀하는 일은 없음 — 최종 권위자는 종료 시 `datetime` 재전송(현재시각 복귀). 진짜 위험은 복귀가 아니라 세션 중 펌웨어가 hands를 옮긴 직후 시간추정 `recalibrate(false)`가 잘못된 위치를 영점으로 래치하는 것(메인 버그와 동일 메커니즘) → 2차 대응으로 차단.
- **검증 상태 (2026-05-18)**: 1차 대응(재진입 차단) — 버튼 클릭 중 다음 클릭 무시 **실기 확인 완료** (v1.1.6 CI 빌드 success). 2차 대응(알림 제스처 억제) — 세션 중 알림 수신은 재현 난이도가 높아 **수일간 일상 사용 중 관찰 예정** (미확인).
- **미해결(후속 PR 후보)**: `writeCompletionHandler` 단일 슬롯 → 큐/딕셔너리화, `recalibrate(false)`를 모터 완료 확인 기반으로 발사. `alert_assign([0,0,0])` 즉시 적용 여부·원복 타이밍 실기 검증 필요(문서는 "안 보내면 안 움직임"만 확인).

### DND(방해 금지) 미작동 (해결됨 여부 불명확)
- **증상**: 펌웨어 `dnd` 명령 전송 시 동작 불안정
- 상세: `docs/resolved/issue-dnd-not-working.md`

---

## 설계 결정 이유

### 폰 찾기 매너모드 우회 (2026-05-01)

매너모드/무음 스위치 ON 상태에서도 알람 사운드가 나도록 다음 조합을 사용:

1. `AVAudioSession` 카테고리 = `.playback` — 무음 스위치 무시 (음악 앱과 동일)
2. 번들된 `Sources/Resources/alarm.wav` (800Hz 0.2s + 1000Hz 0.2s + 0.3s 무음, 두 톤 교차 사이렌 + tanh soft-clip 고조파, 진폭 0.95, 약 30KB) 를 `AVAudioPlayer` 로 무한 루프
3. `Info.plist > UIBackgroundModes` 에 `audio` 추가 — 시계 버튼 BLE 트리거가 보통 앱 백그라운드 상태에서 발생하므로 필요

**기존 버그**: `/System/Library/Audio/UISounds/alarm.caf` 직접 경로는 iOS 앱 샌드박스에서 접근 불가 → `AVAudioPlayer` 생성이 항상 실패 → catch 폴백의 `AudioServicesPlayAlertSound(1005)` 가 매너모드를 존중해서 진동만 발생했음.

**볼륨 강제 재도입 (2026-07-05)**: 무음 스위치는 `.playback` 로 우회되지만 **미디어 음량이 0 이면** 여전히 무음이었음. 과거 `MPVolumeView` 슬라이더 트릭(구 `findphone_max_volume`)은 iOS 16+ 에서 불안정해 제거했었으나, 이번엔 비공개 `AVSystemController.setVolumeTo:forCategory:`(category `"Audio"`) 방식으로 재도입 (`SystemVolume` enum, `FindMyPhone.swift`). 재생 직전 음량을 1.0 으로 강제하고 `stop()` 에서 원래 값(`AVAudioSession.outputVolume` 로 저장)으로 복구. 비공개 API 라 iOS 업데이트로 깨질 수 있어 `NSClassFromString`/IMP 캐스팅 전 구간을 옵셔널 방어 — 실패해도 진동+일반재생으로 폴백. **사이드로드 개인 앱 전용** (App Store 서명엔 부적합). 정석인 Critical Alerts 는 `com.apple.developer.usernotifications.critical-alerts` entitlement 를 Apple 이 승인·프로파일에 실어줘야 해서 SideStore 무료 서명으론 불가.

**진동 병행 (2026-07-05)**: 기존엔 진동이 catch 폴백에만 있었으나, `startVibration()` 으로 소리 성공/실패와 무관하게 1.2s 간격 `kSystemSoundID_Vibrate` 를 항상 병행. 음량 0 우회가 실패하는 극단 상황에서도 위치 파악 가능하도록.

**정지 동작**: 폰 찾기 재생 중엔 `handleButtonEvent` 진입부에서 어떤 버튼 입력이든 흡수해 즉시 정지. 알람이 울릴 때 사용자의 버튼 입력 의도는 거의 100% "꺼라"이므로 매핑된 액션이 잘못 실행되는 위험을 차단. 단 `eventType == 12`("길게 누름 끝") 는 펌웨어가 길게 누름 release 시 자동 발사하는 artifact 이벤트라 제외 — 안 그러면 긴 클릭에 폰 찾기를 매핑한 경우 손 떼는 즉시 자기 자신을 정지시킴.

### MiniMsgPack 직접 구현
외부 MessagePack 라이브러리 없이 자체 구현. Kronaby 프로토콜에서 사용하는 Map 타입 + 정수/바이너리만 필요하므로 완전한 MessagePack 스펙 불필요. 의존성 최소화 목적.

### XcodeGen 사용
`.xcodeproj` 파일을 git에서 제외하고 `project.yml`만 관리. 충돌 방지 + PR 가독성 향상.

### Apple Developer 계정 없이 배포
SideStore + 개인 Apple ID로 설치. 연간 $99 계정 없이 유지 가능. 단, 7일마다 재서명 필요.

### UserDefaults 직접 사용
CoreData/SQLite 없이 전부 UserDefaults + Codable. 설정 데이터 규모가 작고(알람 최대 8개, 히스토리 최대 300건) 복잡한 쿼리 불필요.

---

## 리버스 엔지니어링 자료

- `docs/kronaby-ble-protocol.md` — BLE 프로토콜 전체 스펙 (서비스 UUID, 74개 명령 코드)
- `/home/usbin/claudedocs/keepnaby/docs/reverse-engineering-log.md` — 명령 발견 과정 로그
- `/home/usbin/claudedocs/keepnaby/docs/ble-capture-analysis.md` — 원시 BLE 패킷 분석
- `/home/usbin/claudedocs/keepnaby/docs/bt_*.txt` — 원시 덤프 파일들

---

## 설계 결정: 모스모드 중 크라운 비활성화 (2026-04-28)

모스모드 진입 시 `complications([5, 15, 18])` 전송으로 크라운 complication을 none(15)으로 임시 비활성화. 종료 시 `UserDefaults["kronaby_crown_mode"]`로 복원.

**이유**: 모스 입력 중 실수로 크라운을 건드리면 할당된 complication(타이머 등)이 펌웨어 레벨에서 실행됨. 앱이 버튼 이벤트를 무시해도 펌웨어 자체 동작은 막을 수 없어 complication 자체를 일시 해제하는 방식 선택.

## 미확인 현상: 모스모드 중 바늘 다회전 역방향 움직임 (2026-04-28)

**현상**: 모스 입력 중 특정 버튼 시퀀스 후 시침·분침이 1/60씩 반시계방향으로 여러 바퀴 회전 후 자연 종료. 11시 방향 정렬 후 계속 움직이다 멈춤. 캘리브레이션 미복원.

**현재 추정**: 앱이 recalibrate 모드를 유지하는 동안 펌웨어 native calibration 루틴이 인터럽트된 것으로 의심. 11시(=position 55) 정렬은 공식 앱 calibration home position과 일치 (`stepper_goto([0,55]), [1,55]`). 재현 미성공.

**미해결**: 정확한 트리거 조건 불명. 추가 재현 시 keepnaby 로그 + 버튼 시퀀스 기록 필요.

---

## 설계 결정: 물 섭취 기록 (2026-05-08)

**구조**: `WaterIntakeManager` 가 단일 표준량(`standardAmountML`, default 200ml) + 일일 목표(`dailyGoalML`, default 2000ml) + 90일 기록을 UserDefaults 에 보관. `ButtonAction.drinkWater` 액션이 트리거되면 표준량만큼 추가하고 진동 1회 피드백.

**설계 결정 이유**
- 단일 표준량으로 한 이유: ButtonAction 마다 ml 을 달리 두면 매핑이 복잡해지고, 사용자 의도가 "1잔" 단위라 단일 양으로 충분.
- 90일 retention: 무한 누적 방지 + 7일 차트 + 가벼운 통계 정도면 충분.
- 기록 삭제: 잘못 눌렀을 때(주머니에 넣고 누름 등) 되돌릴 수 있어야 함 → swipe-to-delete 지원.

**관련 파일**
- `Sources/Features/WaterIntakeManager.swift`
- `Sources/UI/WaterIntakeView.swift`
- `Sources/Features/ButtonActionManager.swift` — `.drinkWater` enum + dispatch
- `Sources/UI/ButtonMappingView.swift` — picker "건강" 섹션

---

## TODO

현재 특별히 기록된 TODO 없음. 변경 작업 시 이 섹션에 추가.
