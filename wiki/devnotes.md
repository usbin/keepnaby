<!-- 최종 수정: 2026-04-28 -->

# 개발 노트

## 알려진 이슈

### ANCS 24시간 후 끊김 (해결됨)
- **증상**: BLE 연결 유지 중 24시간 이후 ANCS 알림 수신 중단
- **원인**: CoreBluetooth idle timeout 후 GATT 캐시 만료
- **해결**: 전체 GATT 재협상 로직 추가
- 상세: `docs/resolved/issue-ancs-drops-after-day.md`

### DND(방해 금지) 미작동 (해결됨 여부 불명확)
- **증상**: 펌웨어 `dnd` 명령 전송 시 동작 불안정
- 상세: `docs/resolved/issue-dnd-not-working.md`

---

## 설계 결정 이유

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

## TODO

현재 특별히 기록된 TODO 없음. 변경 작업 시 이 섹션에 추가.
