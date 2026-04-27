<!-- 최종 수정: 2026-04-27 -->

# Keepnaby

Kronaby 아날로그 스마트워치를 iOS에서 제어하는 BLE 컴패니언 앱.  
Kronaby 공식 앱이 단종된 이후 리버스 엔지니어링으로 재구현. 알람, 알림 진동 매핑, 버튼 커스텀 액션, 모스 입력, 위치 기록 등을 지원한다.

**기술 스택**  
Swift 5.10 / SwiftUI / CoreBluetooth / ANCS / HealthKit / BGTaskScheduler  
XcodeGen / GitHub Actions (SideStore `.ipa` 빌드)  
iOS 16.0+, Apple Developer 계정 불필요 (SideStore 사이드로드)

---

## Wiki 페이지 목록

| 페이지 | 내용 |
|--------|------|
| [architecture.md](architecture.md) | 디렉터리 구조, 모듈 관계 |
| [components.md](components.md) | 파일·클래스·함수 역할 표 |
| [setup.md](setup.md) | 빌드, 설치, 배포 방법 |
| [data-flow.md](data-flow.md) | BLE 연결 흐름, 명령 파이프라인 |
| [devnotes.md](devnotes.md) | TODO, 알려진 이슈, 설계 결정 |
