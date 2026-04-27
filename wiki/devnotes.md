<!-- 최종 수정: 2026-04-27 -->

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

## TODO

현재 특별히 기록된 TODO 없음. 변경 작업 시 이 섹션에 추가.
