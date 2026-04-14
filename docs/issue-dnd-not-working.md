# DND(방해금지) 동작 안 하는 이슈

## 증상
- 설정 화면에서 DND를 활성화하고 적용해도 해당 시간대에 알림 진동/바늘이 계속 울림
- 로그: `sendCommand 실패: dnd (char=true, map=nil)` — 현재 코드가 보내는 `dnd` 명령이 펌웨어 commandMap에 없어서 전송 자체가 실패
- iPhone의 집중모드/방해금지모드를 켜도 시계는 ANCS 알림을 계속 수신 (OS 레벨 Focus로는 우회 불가 — 실기기 확인됨)

## 확인된 사실
- Kronaby Nord 펌웨어 commandMap 74개 전수조사 — `dnd` 라는 이름의 명령은 **존재하지 않음** (`docs/kronaby-ble-protocol.md` 549~570 참고)
- `stillness` (cmd 59) 는 별개의 명령 — joakar/kronaby 레퍼런스상 `writeStillness(timeout, window, start, end)` 시그니처, 의미는 **비활동(inactivity) 알림** 용도. DND 아님
- `docs/kronaby-ble-protocol.md:426` 표에 "DND 방해금지 | stillness | ✅" 로 적혀 있지만 이는 잘못된 매핑. 실제로 동작한 적 없음
- iPhone Focus/방해금지모드로도 시계 알림이 차단되지 않음 → ANCS 전달은 iOS Focus 상태와 무관하게 유지됨

## 커밋 이력상 원인
| 커밋 | 변경 | 결과 |
|------|------|------|
| `383b81e` (2026-04-04) | `stillness` 에 `[enabled, startH, startM, endH, endM]` 5-파라미터 전송 | 명령은 나갔지만 stillness 4-파라미터 시그니처와 안 맞아 동작 안 함(추정) |
| `0eadcc7` (2026-04-14) | "fix:dnd 동작 안 하는 이슈" — 명령명을 `stillness` → `dnd` 로 변경 | `dnd` 가 commandMap에 없어 전송 자체가 실패(`map=nil`). 현재 상태 |

## 현재 코드 위치
- `Sources/UI/WatchSettingsView.swift:96` — 적용 버튼에서 `sendCommand(name: "dnd", ...)` 호출
- `Sources/KeepnabyApp.swift:59` — 연결 시 재전송 경로에서 동일 호출

## 가능한 방향
1. **앱 측 스케줄러로 에뮬레이션** — DND 시간대 진입 시 `ancs_filter` 슬롯을 전부 빈 삭제 필터로 덮어씌우고 종료 시 원래 필터 복원. 백그라운드 정확성 문제(`BGAppRefreshTask` 타이밍 불확정) 있음. **보류**
2. **iOS Focus 모드 안내** — 실기기 테스트 결과 **효과 없음**. ANCS 전달이 Focus 상태와 독립적으로 유지됨. **폐기**
3. **DND 기능 제거** — UI / UserDefaults / 재전송 로직 전부 삭제. **보류**

## 아직 시도해볼 것
1. **공식 APK 역공학으로 DND 전송 방식 확인** — 공식 앱에 DND UI가 있었던 것으로 기억. APK 디컴파일본이 있으니 실제로 어떤 명령/키 조합을 쓰는지 확인 예정 (퇴근 후). `settings` (cmd 46) 의 특정 키(예: 기존 코드의 154/160/174/176/178 외)로 보내거나, 미사용 명령 중 하나일 가능성
2. 위에서 DND 전송 방식이 확인되면 그대로 포팅 → 동작 검증

## 기술 배경
- ANCS 는 iOS 가 BLE peripheral 에 알림을 직접 전달하는 프로토콜. 앱 개입 없음
- 시계 펌웨어가 ANCS 에 직접 구독하므로, 앱에서 DND 를 구현하려면:
  - 펌웨어 자체 DND 기능을 쓰거나 (전용 명령 or settings 키)
  - `ancs_filter` 를 시간대별로 토글하거나
  - iOS 측에서 ANCS 전달을 막아야 함 (현재 iOS API 로는 불가 — Focus 모드로도 안 됨)
