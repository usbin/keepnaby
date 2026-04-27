<!-- 최종 수정: 2026-04-27 -->

# 설치 및 빌드

## 개발 환경 요구사항

| 항목 | 버전 |
|------|------|
| Xcode | 15.0+ |
| Swift | 5.10 |
| iOS 배포 대상 | 16.0+ |
| XcodeGen | 최신 (`brew install xcodegen`) |

외부 패키지·CocoaPods 의존성 없음.

---

## 로컬 빌드

```bash
# 1. 저장소 클론
git clone <repo-url>
cd keepnaby

# 2. Xcode 프로젝트 생성 (project.yml → keepnaby.xcodeproj)
xcodegen generate

# 3. Xcode에서 열기
open keepnaby.xcodeproj
```

Xcode에서 개발 팀을 개인 Apple ID로 설정 후 빌드.

---

## 환경변수 / 설정값

환경변수 없음. 앱 설정은 전부 런타임 UserDefaults에 저장.

**Info.plist 주요 값**

| 키 | 값 | 용도 |
|----|-----|------|
| `BGTaskSchedulerPermittedIdentifiers` | `com.usbin.kronaby.sync` | 백그라운드 동기화 태스크 ID |
| Bundle ID | `com.usbin.keepnaby` | 앱 식별자 |

---

## GitHub Actions CI 빌드

`.github/workflows/build.yml`이 push 시 자동 실행됨.

- 결과물: `.ipa` 아티팩트 (SideStore 호환)
- Apple Developer 계정 불필요

---

## 기기 설치 방법

### SideStore (권장)
1. SideStore 앱 설치 (LocalDevVPN 방식)
2. CI 빌드 결과 `.ipa` 다운로드
3. SideStore에서 `.ipa` 설치
4. 7일마다 SideStore 앱으로 재서명 갱신

### Sideloader CLI
Windows/macOS 커맨드라인 툴로 `.ipa` 직접 설치.

---

## 필요 기기 권한 (최초 실행 시 승인 필요)

| 권한 | 용도 |
|------|------|
| Bluetooth | Kronaby BLE 통신 |
| 위치 (항상 허용) | 버튼 트리거 GPS 기록 |
| HealthKit (읽기) | 걸음 수 읽기 |
