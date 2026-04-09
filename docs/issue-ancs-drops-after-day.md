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

## 추정 원인 (우선순위 순)

### 1. ~~keepAlive ANCS 명령 반복 재전송이 ANCS를 불안정하게 만듦~~ → 재전송 주기/범위 문제
- ~~Keepnaby: 10분마다 `complications([5, mode, 18])` + `ancs_filter` 재전송~~
- ~~공식 앱: 설정을 한 번만 보내고 건드리지 않음~~
- **공식 APK 역공학 결과: "공식 앱은 재전송 안 한다"는 전제가 틀렸음**
- 공식 앱은 `WorkManager`로 **1시간마다** 전체 sync (`onHandlePeriodicTasks` → `doSync`) 수행
- sync에 ANCS 필터 35개 슬롯 전체 재전송 포함
- 이전 Keepnaby 시도(10분, 일부 슬롯만)와 공식 앱(1시간, 전체 35슬롯)은 주기와 범위가 달랐음
- **현재 조치: 1시간 주기 전체 설정 재전송 구현 (공식 앱 방식)**

### 2. ANCS 필터 슬롯 범위 부족
- 공식 앱: **0~34 (35개 슬롯)** 전체 관리, 미사용 슬롯에도 빈 삭제 필터 전송
- Keepnaby: 0~12 (13개)만 삭제 → 13~34에 잔여 필터 남을 가능성
- **현재 조치: 삭제 범위 0~34로 확장 완료**

### 3. `didModifyServices` 미구현
- iOS가 GATT 테이블 변경을 알릴 때 Keepnaby가 무시하고 있었음
- 특성 참조가 stale해져서 ANCS 관련 상태가 무효화될 수 있음
- **조치 완료: `didModifyServices` 구현 완료 — 서비스 변경 시 자동 재검색**

### 4. `periodic` (cmd 38) 미사용
- commandMap에 존재하지만 Keepnaby에서 사용하지 않음
- 공식 앱이 이 명령으로 시계에 주기적 heartbeat를 설정할 수 있음
- 공식 APK 역공학에서는 이 명령의 직접 사용을 확인하지 못함 (디컴파일 실패 영역에 있을 가능성)

### 5. 공식 앱이 보내는 미확인 명령
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

## 현재 시도 중
1. **1시간 주기 전체 설정 재전송** — 공식 앱 방식으로 구현 완료, 실기기 검증 필요
2. **ANCS 필터 슬롯 0~34 전체 관리** — 삭제 범위 확장 완료, 실기기 검증 필요

## 아직 시도해볼 것 (위 시도가 실패할 경우)
1. **`periodic` 명령 (cmd 38) 조사** — 디컴파일 실패 영역에 있을 수 있음. 다른 디컴파일러(Procyon, CFR) 시도
2. **iOS 26.3 Notification Forwarding** — ANCS를 완전히 우회하는 방법. 현재 EU 한정으로 한국 미지원

## 기술 배경
- ANCS는 iOS가 BLE peripheral에 알림을 전달하는 프로토콜
- 시계 펌웨어가 직접 iOS ANCS 서비스에 구독 — 앱은 설정만 전달
- iOS 블루투스 토글은 전체 BLE 스택을 리셋하여 모든 GATT 캐시/세션 초기화
- `cancelPeripheralConnection`은 단일 peripheral만 끊으므로 iOS 내부 ANCS 상태를 리셋하지 못함
