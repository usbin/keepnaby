<!-- 최종 수정: 2026-05-08 -->

# 컴포넌트

## 주요 데이터 모델 (`ButtonActionManager.swift`)

| 타입 | 필드 | 설명 |
|------|------|------|
| `ButtonAction` | `type` | 액션 종류 (none/findPhone/urlRequest 등) |
| | `label` | 모스 명령 설명 메모 (예: "Computer ON") |
| | `urlString` | URL 직접 입력값 |
| | `urlPresetID` | 선택된 Webhook 프리셋 UUID (nil=직접 입력) |
| | `urlPath` | 프리셋 사용 시 경로 (예: `/api/on`) |
| | `urlParams` | 프리셋 사용 시 파라미터 (예: `token=abc`) |
| `WebhookPreset` | `id` / `name` / `baseURL` | Webhook 주소 프리셋 (이름 + base URL) |

---

## BLE 계층 (`Sources/BLE/`)

| 파일 | 역할 |
|------|------|
| `BLEManager.swift` | CoreBluetooth 중앙 매니저. 스캔→연결→핸드셰이크→명령 디스패치, 배터리·걸음 수 폴링 |
| `KronabyProtocol.swift` | 명령 인코딩 래퍼. `ButtonEvent` 구조체, 바이너리 페이로드 생성 |
| `MiniMsgPack.swift` | 경량 MessagePack 인코더/디코더 (외부 라이브러리 미사용) |
| `BLEConstants.swift` | BLE 서비스·캐릭터리스틱 UUID 상수 정의 |
| `BackgroundSyncScheduler.swift` | `BGTaskScheduler`로 백그라운드 BLE 동기화 등록·실행 |

### BLEManager 상태 기계

```
disconnected → scanning → connecting → handshaking → connected
```

핸드셰이크: `map_cmd` 폴 3회 (920000·920001·920002) → 워치 지원 명령 74개 목록 수신  
Bluetooth State Restoration 활성화로 백그라운드 재연결 지원

---

## Features 계층 (`Sources/Features/`)

| 파일 | 역할 |
|------|------|
| `ButtonActionManager.swift` | 버튼 이벤트 → 액션 매핑. 버튼 3개 × 이벤트 유형으로 10가지 조합 처리. 모스 디코더 통합. Webhook 프리셋 관리(base+path+params 조합) |
| `NotificationMappingManager.swift` | ANCS 필터링. 앱 번들 ID → 진동 패턴 슬롯(3개) 매핑 |
| `AlarmManager.swift` | 알람 CRUD. 최대 8개, 요일 비트마스크로 워치 펌웨어에 전송 |
| `LocationRecorder.swift` | GPS 캡처·역지오코딩. Google Maps·Naver지도·카카오맵 URL 스킴 생성 |
| `ActionHistoryManager.swift` | 버튼·모스 액션 실행 이력 저장 (최대 300건, UserDefaults) |
| `MorseDecoder.swift` | 모스 코드 ↔ 영문자·숫자 변환 테이블 (A-Z, 0-9) |
| `MusicController.swift` | 음악 재생 제어 래퍼 (재생/일시정지/다음/이전) |
| `FindMyPhone.swift` | 매너모드/무음 모드 무시하고 알람 사운드 재생 (`Resources/alarm.wav` 30s 루프). 재생 중 시계 어떤 버튼이든 누르면 즉시 정지 |
| `WaterIntakeManager.swift` | 물 섭취 기록 (UserDefaults). 표준 1회량/일일 목표/90일 보관, today total·progress·삭제 API |

### 모스 입력 흐름

1. 하단 버튼 길게 누르기 → 모스 입력 모드 진입 (크라운 complication 자동 비활성화)
2. 하단 버튼 1회=점(·), 2회=대시(−)
3. 상단 버튼 1회=문자 확정, 2회=점진 취소, 길게=전체 취소
4. 피드백: 분침(·=+5분, −=+10분), 시침(입력된 문자 수 × 5분)
5. 최대 11자, 하단 버튼 길게=실행
6. 종료 시 크라운 complication 자동 복원

---

## UI 계층 (`Sources/UI/`)

| 파일 | 화면 역할 |
|------|-----------|
| `ConnectionView.swift` | 루트 화면. BLE 스캔 목록·연결 상태·빠른 액션 |
| `WatchSettingsView.swift` | 워치 펌웨어 설정. 시간·타임존·컴플리케이션 |
| `CalibrationView.swift` | 바늘 영점 조정 UI |
| `ButtonMappingView.swift` | 10가지 버튼 조합에 액션 할당. `ActionDetailView`, `WebhookPresetListView`, `WebhookPresetEditView` 포함 |
| `MorseMappingView.swift` | 모스 코드 명령에 액션 할당 (최대 11자). 설명(label) 입력 포함 |
| `NotificationMappingView.swift` | 앱 → 진동 슬롯 할당 (사전 목록 + 커스텀 번들 ID) |
| `AlarmView.swift` | 알람 추가·수정·삭제, 시각·반복 요일 설정 |
| `LocationHistoryView.swift` | 저장된 GPS 위치 목록·지도 링크 |
| `ActionHistoryView.swift` | 버튼 이벤트 로그 조회·재실행 |
| `TimeSettingView.swift` | 시간·타임존 수동 동기화 |
| `ComplicationsView.swift` | 크라운 컴플리케이션 설정 (날짜·걸음·세계시·스톱워치) |
| `WaterIntakeView.swift` | 물 섭취 진행도(Gauge), 표준량/목표 Stepper, 오늘 기록 swipe-delete, 최근 7일 합계 |

---

## 진입점

**`KeepnabyApp.swift`** — SwiftUI `@main`. `BLEManager`, `ButtonActionManager` 등 주요 매니저를 `@StateObject`로 생성하고 `@EnvironmentObject`로 뷰 트리에 주입.
