# ANCS 하루 후 끊김 이슈

## 증상
- 연결 후 ~6-8시간(자고 일어나면) ANCS만 죽음
- 시계 ↔ 폰 BLE 통신은 정상 (명령 주고받기 가능)
- iPhone 알림을 시계가 수신하지 못함
- **블루투스 끄고 켜면 해결됨**
- 공식 Kronaby 앱에서는 이 문제 없었음

## 확인된 사실
- BLE 연결 자체는 끊기지 않음 — ANCS만 선택적으로 죽음
- `cancelPeripheralConnection` → 재연결로는 ANCS 복구 안 됨
- 앱 내 연결 해제 → 앱 재시작 → 자동 연결에서도 ANCS 복구 안 됨
- iOS 블루투스 토글(전체 BLE 스택 리셋)만이 복구 방법
- 공식 앱은 문제 없음 → 펌웨어 결함이 아닌 Keepnaby 측 문제

## 효과 없었던 시도
| 시도 | 결과 |
|------|------|
| 6시간 주기 `cancelPeripheralConnection` 강제 재연결 | ANCS 복구 안 됨 (iOS BLE 스택 리셋이 아니라 단일 peripheral disconnect라서). 제거됨 |
| `BGAppRefreshTask`로 백그라운드에서 강제 재연결 | 위와 같은 이유로 무의미. 제거됨 |
| 10분 keepAlive에서 `complications`/`ancs_filter` 반복 재전송 | 10분 간격 + 일부 슬롯만 재전송. "공식 앱은 안 한다"고 판단해 제거. **→ 후에 공식 APK 역공학으로 이 전제가 틀렸음을 확인 (공식 앱은 1시간 간격으로 35개 전체 슬롯 재전송)** |
| `onConnected`에서 ANCS 리셋 사이클 (`complications [5,mode,0]` + `alert_assign [0,0,0]` → 2초 후 정상값 재전송) | 재연결 시 ANCS 끄기→켜기로 강제 리프레시 시도. 효과 없음. 제거됨 |
| keepAlive/ANCS 명령 반복 재전송 모두 제거 후 하루 테스트 | ANCS 여전히 6-8시간 후 끊김. 재전송 제거가 해결책 아님 확인 |
| 1시간 주기 `Timer.scheduledTimer`로 전체 설정 재전송 | Timer는 iOS suspended 상태에서 멈추므로 **밤새 sync가 0회 실행됨**. 사실상 무효. BGAppRefreshTask로 교체 (2026-04-10) |

## 추정 원인 (우선순위 순)

### 1. ~~keepAlive ANCS 명령 반복 재전송이 ANCS를 불안정하게 만듦~~ → 재전송 주기/범위 문제 → **Timer가 백그라운드에서 동작하지 않음**
- ~~Keepnaby: 10분마다 `complications([5, mode, 18])` + `ancs_filter` 재전송~~
- ~~공식 앱: 설정을 한 번만 보내고 건드리지 않음~~
- **공식 APK 역공학 결과: "공식 앱은 재전송 안 한다"는 전제가 틀렸음**
- 공식 앱은 `WorkManager`로 **1시간마다** 전체 sync (`onHandlePeriodicTasks` → `doSync`) 수행
- sync에 ANCS 필터 35개 슬롯 전체 재전송 포함
- 이전 Keepnaby 시도(10분, 일부 슬롯만)와 공식 앱(1시간, 전체 35슬롯)은 주기와 범위가 달랐음
- ~~현재 조치: 1시간 주기 전체 설정 재전송 구현 (공식 앱 방식)~~
- **추가 발견 (2026-04-10): `Timer.scheduledTimer`는 iOS가 앱을 suspend하면 멈춤. 즉 밤새 6-8시간 동안 sync가 한 번도 실행되지 않았음. Android `WorkManager`와 근본적으로 다른 메커니즘**
- **현재 조치: `BGAppRefreshTask`로 백그라운드 sync 보완 구현 (Timer + BGTask 병행)**

### 2. iOS가 장시간 GATT 비활성 연결에서 ANCS를 비활성화
- Apple Developer Forums #764999에서 동일 증상 보고 — 장시간 후 ANCS "remove" 메시지 폭주 후 알림 수신 중단
- ANCS 공식 스펙: "the ANCS is **not guaranteed to always be present**" — iOS가 언제든 unpublish/republish 가능
- Timer가 백그라운드에서 안 돌면 → 밤새 GATT 활동이 0 → iOS가 ANCS 비활성화하는 조건에 해당할 수 있음
- 커뮤니티 제안: 주기적 GATT read/write로 연결 활성 유지
- **현재 조치: `BGAppRefreshTask`에서 `vbat` 조회(중립적 GATT 활동) + 전체 설정 재전송**

### 3. ANCS 필터 슬롯 범위 부족
- 공식 앱: **0~34 (35개 슬롯)** 전체 관리, 미사용 슬롯에도 빈 삭제 필터 전송
- Keepnaby: 0~12 (13개)만 삭제 → 13~34에 잔여 필터 남을 가능성
- **조치 완료: 삭제 범위 0~34로 확장 완료**

### 4. `didModifyServices` 미구현
- iOS가 GATT 테이블 변경을 알릴 때 Keepnaby가 무시하고 있었음
- 특성 참조가 stale해져서 ANCS 관련 상태가 무효화될 수 있음
- **조치 완료: `didModifyServices` 구현 완료 — 서비스 변경 시 자동 재검색**

### 5. `didUpdateNotificationStateFor` 미구현
- iOS가 notify 구독 상태를 변경해도 Keepnaby가 감지하지 못했음
- ANCS 관련 GATT 세션이 만료되어 subscription이 해제될 때 재구독 불가
- **조치 완료 (2026-04-10): 구현 완료 — notify 해제 감지 시 자동 재구독 + 로그**

### 6. `periodic` (cmd 38) 미사용
- commandMap에 존재하지만 Keepnaby에서 사용하지 않음
- 시계가 주기적으로 앱에 데이터를 보내는 명령이라면, iOS가 BLE 이벤트로 앱을 깨워줌 → BGTask 없이도 keepalive 가능
- 공식 APK 역공학에서는 이 명령의 직접 사용을 확인하지 못함 (디컴파일 실패 영역에 있을 가능성)
- **현재 조치 (2026-04-10): 연결 시 `periodic(3600)` 전송하여 동작 탐색 중. 시계 응답 관찰 필요**

### 7. 공식 앱이 보내는 미확인 명령
- 공식 APK의 핵심 메서드(`onHandlePeriodicTasks`, `doSync`)가 JADX 디컴파일 실패
- 이 메서드들 안에 추가 명령이 있을 수 있음
- 확인 방법: 다른 디컴파일러(Procyon, CFR) 시도 또는 smali 직접 분석

## 공식 APK 역공학 결과 (2026-04-09)

공식 Android APK (JADX 디컴파일)을 분석하여 연결 유지 메커니즘 확인:

### 공식 앱의 연결 유지 전략
1. **1시간 주기 sync** — `WorkManager` `PeriodicWorkRequest(1시간)` → `onHandlePeriodicTasks()` → 전체 설정 재전송
2. **ANCS 필터 35개 슬롯 전체 관리** — 인덱스 0~34, 미사용 슬롯에 빈 삭제 필터(`[index]`) 전송
3. **sync 시 전체 설정 재전송** — complications, alert_assign, ancs_filter 등 모두 포함
4. **Foreground Service** — `DeviceService`로 앱 프로세스 유지

### 공식 앱 vs 이전 Keepnaby 시도 비교
| | 공식 앱 | 이전 Keepnaby keepAlive |
|--|---------|------------------------|
| 주기 | **1시간** | 10분 |
| ANCS 슬롯 범위 | **0~34 (35개)** | 활성 슬롯만 |
| 재전송 범위 | **전체 설정** | complications + ancs_filter만 |

### 디컴파일 한계
- `onHandlePeriodicTasks`, `doSync` 등 핵심 메서드가 JADX 디컴파일 실패 (코루틴 상태머신)
- 이 메서드들 안에 추가 명령이 있을 가능성 있음

## 현재 시도 중 (2026-04-10)
1. **`BGAppRefreshTask`로 백그라운드 sync** — Timer가 suspended 상태에서 동작하지 않는 문제 해결. 30분 간격 요청 (실행 시점은 iOS 결정). sync 시 `vbat` 조회(GATT keepalive) + 전체 설정 재전송. 실기기 검증 필요
2. **`periodic` (cmd 38) 탐색** — 연결 시 `periodic(3600)` 전송. 시계가 주기적 데이터를 보내는 명령이면 BGTask 없이도 iOS가 앱을 깨워줌. 시계 응답 관찰 필요
3. **`didUpdateNotificationStateFor` 구현** — notify 구독 해제 감지 + 자동 재구독. 진단 목적
4. **1시간 주기 전체 설정 재전송** — 공식 앱 방식 구현 완료 (Timer + BGTask 병행), 실기기 검증 필요
5. **ANCS 필터 슬롯 0~34 전체 관리** — 삭제 범위 확장 완료, 실기기 검증 필요

## 아직 시도해볼 것 (위 시도가 실패할 경우)
1. **`periodic` 명령 값 형식 변경** — `3600`이 안 되면 `[1, 3600]`, `[3600, 1]` 등 시도
2. **다른 디컴파일러로 공식 APK 재분석** — Procyon, CFR로 `onHandlePeriodicTasks`, `doSync` 디컴파일 재시도
3. **iOS 26.3 Notification Forwarding** — ANCS를 완전히 우회하는 방법. 현재 EU 한정으로 한국 미지원

## 커뮤니티 조사 결과 (2026-04-10)

### Apple Developer Forums #764999 — 동일 증상 보고
- 장시간 BLE 연결 후 ANCS "remove" 메시지 폭주 → 이후 알림 수신 중단
- 전화 알림은 계속 동작, 메시지/앱 알림만 중단
- Apple 엔지니어가 버그 리포트 요청 → 비정상 동작으로 인식

### ANCS 스펙의 핵심
- "the ANCS is **not guaranteed to always be present**" — iOS가 언제든 unpublish/republish 가능
- Service Changed 특성을 모니터링하지 않으면 CCCD 구독이 stale해질 수 있음
- Keepnaby 구조상 ANCS CCCD는 시계 펌웨어가 관리하므로 앱에서 직접 제어 불가

### iOS 백그라운드 BLE 앱의 Timer 문제
- `Timer.scheduledTimer`는 iOS가 앱을 suspended 상태로 전환하면 **정지됨**
- `bluetooth-central` 백그라운드 모드가 있어도, BLE 이벤트가 없으면 앱은 suspended
- Android `WorkManager`는 앱이 죽어도 OS가 깨워서 실행 → iOS에는 `BGAppRefreshTask`가 대응

## 기술 배경
- ANCS는 iOS가 BLE peripheral에 알림을 전달하는 프로토콜
- 시계 펌웨어가 직접 iOS ANCS 서비스에 구독 — 앱은 설정만 전달
- iOS 블루투스 토글은 전체 BLE 스택을 리셋하여 모든 GATT 캐시/세션 초기화
- `cancelPeripheralConnection`은 단일 peripheral만 끊으므로 iOS 내부 ANCS 상태를 리셋하지 못함
- `Timer.scheduledTimer`는 앱이 foreground/background active 상태에서만 동작, suspended 상태에서는 정지
- `BGAppRefreshTask`는 iOS가 시스템 상황에 따라 앱을 깨워서 짧은 작업 실행 가능 (정확한 주기 보장은 안 됨)
