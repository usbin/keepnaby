# [해결됨] ANCS 하루 후 끊김 이슈

**해결 날짜**: 2026-04-10 수정, 2026-04-15 해결 확인 (1주일간 미재발)

## 증상
- 연결 후 ~6-8시간(자고 일어나면) ANCS만 죽음
- 시계 ↔ 폰 BLE 통신은 정상 (명령 주고받기 가능)
- iPhone 알림을 시계가 수신하지 못함
- 블루투스 끄고 켜면 해결됨

## 근본 원인
**iOS가 장시간 GATT 비활성 연결에서 ANCS를 비활성화.**

ANCS 스펙: "the ANCS is not guaranteed to always be present" — iOS가 언제든 unpublish/republish 가능. 밤새 GATT 활동이 없으면 iOS가 ANCS를 비활성화하는 조건에 해당.

## 해결 방법
`BGAppRefreshTask`로 주기적 GATT keepalive (`vbat` 조회) 실행. iOS가 BLE 연결이 여전히 활성 상태임을 인식하게 함.

### 적용된 수정 (복합적)
1. **`BGAppRefreshTask`로 백그라운드 keepalive** — `vbat` 조회로 주기적 GATT 활동 유지. Timer는 iOS suspended 상태에서 멈추므로 BGTask가 핵심
2. **`didModifyServices` 구현** — iOS가 GATT 테이블 변경 시 서비스 자동 재검색
3. **`didUpdateNotificationStateFor` 구현** — notify 구독 해제 감지 시 자동 재구독
4. **ANCS 필터 슬롯 0~34 전체 관리** — 공식 앱과 동일 범위로 확장

### 불필요했던 것 (2026-04-15 제거)
- **1시간 주기 전체 설정 재전송** — 펌웨어가 설정을 비휘발성 메모리에 저장하므로 불필요. GATT keepalive만으로 충분
- **재연결 시 전체 설정 재전송** — 동일 이유. `onboarding_done(1)` + `config_base([1,1])`만 전송하도록 축소

## 효과 없었던 시도
| 시도 | 결과 |
|------|------|
| `cancelPeripheralConnection` 강제 재연결 | iOS BLE 스택 리셋이 아니라 단일 peripheral disconnect라 ANCS 복구 안 됨 |
| `BGAppRefreshTask`로 강제 재연결 | 위와 같은 이유로 무의미 |
| 10분 keepAlive에서 `complications`/`ancs_filter` 반복 재전송 | 주기와 범위가 부족했고, Timer가 suspended에서 멈춤 |
| `complications [5,mode,0]` + `alert_assign [0,0,0]` → 2초 후 정상값 재전송 | ANCS 리셋 시도. 효과 없음 |
| iPhone Focus/방해금지모드 | ANCS 전달이 Focus 상태와 독립적으로 유지됨 |

## 미해결 관련 이슈
시계가 물리적으로 멀어져서 BLE 연결이 완전히 끊긴 후 돌아오면 ANCS가 죽는 경우가 있음. 재연결 시 ANCS 설정 재전송 타이밍 문제로 추정. → `docs/issue-ancs-after-reconnect.md`로 별도 추적 예정.

## 기술 배경
- ANCS는 iOS가 BLE peripheral에 알림을 직접 전달하는 프로토콜
- 시계 펌웨어가 직접 iOS ANCS 서비스에 구독 — 앱은 설정만 전달
- `Timer.scheduledTimer`는 iOS suspended 상태에서 정지 → `BGAppRefreshTask`로 보완 필수
- `BGAppRefreshTask`는 iOS가 시스템 상황에 따라 앱을 깨워 짧은 작업 실행 (정확한 주기 보장 안 됨, 보통 30분~수 시간)
