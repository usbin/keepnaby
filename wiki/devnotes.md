<!-- 최종 수정: 2026-05-01 -->

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

### 폰 찾기 매너모드 우회 (2026-05-01)

매너모드/무음 스위치 ON 상태에서도 알람 사운드가 나도록 다음 조합을 사용:

1. `AVAudioSession` 카테고리 = `.playback` — 무음 스위치 무시 (음악 앱과 동일)
2. 번들된 `Sources/Resources/alarm.wav` (800Hz 0.2s + 1000Hz 0.2s + 0.3s 무음, 두 톤 교차 사이렌 + tanh soft-clip 고조파, 진폭 0.95, 약 30KB) 를 `AVAudioPlayer` 로 무한 루프
3. `Info.plist > UIBackgroundModes` 에 `audio` 추가 — 시계 버튼 BLE 트리거가 보통 앱 백그라운드 상태에서 발생하므로 필요

**기존 버그**: `/System/Library/Audio/UISounds/alarm.caf` 직접 경로는 iOS 앱 샌드박스에서 접근 불가 → `AVAudioPlayer` 생성이 항상 실패 → catch 폴백의 `AudioServicesPlayAlertSound(1005)` 가 매너모드를 존중해서 진동만 발생했음.

**제거된 옵션**: `findphone_max_volume` (시스템 볼륨 강제 최대화) — `MPVolumeView` 슬라이더 트릭이 iOS 16+에서 불안정하고 실사용 가치 낮아 삭제. iOS 는 시스템 볼륨을 코드로 안정적으로 설정할 공개 API를 제공하지 않음 — 대신 사운드 파일 자체의 진폭을 0.95 까지 끌어올리고 두 톤 교차 + soft-clip 고조파로 체감 음량을 키우는 방향으로 대응.

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

## TODO

현재 특별히 기록된 TODO 없음. 변경 작업 시 이 섹션에 추가.
