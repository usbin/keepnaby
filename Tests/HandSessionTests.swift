import XCTest
@testable import Keepnaby

/// 바늘 캘리브레이션 어긋남 재현 — BLE 명령 시퀀스로 검증 (실제 시계 없이 타이머 실시간 구동).
/// 불변식: recalibrate(true)/(false)는 엄격히 교대해야 함 — 활성 중 재진입 = 영점 오염.
final class HandSessionTests: XCTestCase {
    private var ble: BLEManager!
    private var manager: ButtonActionManager!
    private var sent: [(time: Date, name: String, value: Any)] = []

    override func setUp() {
        sent = []
        ble = BLEManager()
        ble.connectionState = .connected
        ble.commandInterceptor = { [unowned self] name, value in self.sent.append((Date(), name, value)) }
        manager = ButtonActionManager()
        manager.bleManager = ble
        manager.mappings = ["0_1": ButtonAction(type: .showDate)]  // 상단 1회 = 날짜 표시
    }

    private func wait(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private var recalibrates: [Bool] { sent.filter { $0.name == "recalibrate" }.compactMap { $0.value as? Bool } }

    private func assertRecalibrateAlternates(file: StaticString = #filePath, line: UInt = #line) {
        let seq = recalibrates
        let ok = !seq.isEmpty && seq.enumerated().allSatisfy { $0.element == ($0.offset % 2 == 0) } && seq.count % 2 == 0
        XCTAssertTrue(ok, "recalibrate 시퀀스 비정상: \(seq)", file: file, line: line)
    }

    /// A: 모스 종료(0 복귀) 구간에 누른 버튼이 새 바늘 세션을 시작하면 안 됨.
    func testButtonDuringMorseExitIsIgnored() {
        manager.handleButtonEvent(button: 2, event: 2)  // 모스 진입
        wait(4)
        manager.handleButtonEvent(button: 2, event: 2)  // 빈 버퍼 종료
        wait(0.5)
        manager.handleButtonEvent(button: 0, event: 1)  // 종료 진행 중 날짜 표시 시도
        wait(15)
        assertRecalibrateAlternates()
    }

    /// A: 일반 표시 세션 중 하단 길게 누름으로 모스모드에 진입하면 안 됨.
    func testLongPressDuringDisplaySessionIsIgnored() {
        manager.handleButtonEvent(button: 0, event: 1)  // 날짜 표시
        wait(0.5)
        manager.handleButtonEvent(button: 2, event: 2)  // 세션 중 모스 진입 시도
        XCTAssertFalse(manager.isMorseMode)
        wait(15)
        assertRecalibrateAlternates()
    }

    /// B: 모스모드 동안 펌웨어 알림 제스처를 억제하고 종료 시 원복해야 함.
    func testMorseModeSuppressesAlertGesture() {
        manager.handleButtonEvent(button: 2, event: 2)
        wait(4)
        manager.handleButtonEvent(button: 2, event: 2)
        wait(4)
        let names = sent.map(\.name)
        let assigns = sent.enumerated().filter { $0.element.name == "alert_assign" }
        XCTAssertEqual(assigns.count, 2, "alert_assign 억제/원복 누락: \(names)")
        guard assigns.count == 2,
              let firstRecal = names.firstIndex(of: "recalibrate"),
              let lastRecal = names.lastIndex(of: "recalibrate") else { return }
        XCTAssertEqual(assigns[0].element.value as? [Int], [0, 0, 0])
        XCTAssertLessThan(assigns[0].offset, firstRecal, "억제가 recalibrate(true)보다 늦음")
        XCTAssertGreaterThan(assigns[1].offset, lastRecal, "원복이 recalibrate(false)보다 이름")
    }

    /// C: recalibrate(true) 직후 12시 정렬이 끝나기 전에 recalibrate_move를 보내면 안 됨.
    func testMorseFeedbackWaitsForHoming() {
        manager.handleButtonEvent(button: 2, event: 2)  // 모스 진입
        manager.handleButtonEvent(button: 2, event: 1)  // 점
        manager.handleButtonEvent(button: 0, event: 1)  // 문자 확정 → 분침 피드백
        wait(5)
        guard let start = sent.first(where: { $0.name == "recalibrate" })?.time,
              let move = sent.first(where: { $0.name == "recalibrate_move" })?.time else {
            return XCTFail("명령 누락: \(sent.map(\.name))")
        }
        XCTAssertGreaterThanOrEqual(move.timeIntervalSince(start), 1.4, "정렬 대기 없이 바늘 이동")
    }
}
