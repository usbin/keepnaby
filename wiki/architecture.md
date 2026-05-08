<!-- 최종 수정: 2026-05-08 -->

# 아키텍처

## 디렉터리 구조

```
keepnaby/
├── Sources/
│   ├── KeepnabyApp.swift          # SwiftUI @main 진입점, 의존성 주입
│   ├── Info.plist                 # 앱 메타데이터·권한 선언
│   ├── Keepnaby.entitlements      # HealthKit, Wi-Fi Info 권한
│   ├── Assets.xcassets/           # 앱 아이콘·이미지
│   ├── Resources/                 # 번들 리소스 (alarm.wav 등)
│   ├── BLE/                       # CoreBluetooth + 프로토콜 계층
│   ├── Features/                  # 비즈니스 로직 매니저
│   └── UI/                        # SwiftUI 뷰
├── docs/
│   ├── kronaby-ble-protocol.md    # BLE 프로토콜 전체 스펙
│   └── resolved/                  # 해결된 이슈 기록
├── wiki/                          # 프로젝트 위키 (이 디렉터리)
├── .github/workflows/build.yml   # GitHub Actions CI
└── project.yml                    # XcodeGen 프로젝트 정의
```

## 모듈 관계

```
┌─────────────────────────────────────────────────────────┐
│                        UI Layer                         │
│  ConnectionView · WatchSettingsView · ButtonMappingView │
│  AlarmView · NotificationMappingView · MorseMappingView │
│  LocationHistoryView · ActionHistoryView · 기타          │
└──────────────────────┬──────────────────────────────────┘
                       │ @EnvironmentObject / ObservableObject
┌──────────────────────▼──────────────────────────────────┐
│                    Features Layer                        │
│  ButtonActionManager  ←─ ButtonEvent                    │
│  NotificationMappingManager  (ANCS 필터링)               │
│  AlarmManager  ·  LocationRecorder                      │
│  ActionHistoryManager  ·  MorseDecoder                  │
│  MusicController  ·  FindMyPhone                        │
│  WaterIntakeManager  (물 섭취 기록)                       │
└──────────────────────┬──────────────────────────────────┘
                       │ 명령 인코딩 요청
┌──────────────────────▼──────────────────────────────────┐
│                      BLE Layer                          │
│  BLEManager  (CoreBluetooth 상태 기계)                   │
│    └─ KronabyProtocol  (명령 래퍼)                       │
│         └─ MiniMsgPack  (MessagePack 직렬화)             │
│  BLEConstants  (UUID 정의)                               │
│  BackgroundSyncScheduler  (BGTaskScheduler)             │
└──────────────────────┬──────────────────────────────────┘
                       │ CoreBluetooth BLE
              ┌────────▼────────┐
              │  Kronaby Watch   │
              └─────────────────┘
```

## 데이터 저장

- **UserDefaults** — 버튼 매핑, 알람 목록, 알림 매핑, 액션 히스토리 (최대 300건)
- **파일 없음** — 별도 로컬 DB 미사용, 모든 설정은 UserDefaults 직렬화
