import SwiftUI
import UserNotifications

@main
struct KeepnabyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var bleManager = BLEManager()
    @StateObject private var actionManager = ButtonActionManager()
    @StateObject private var locationRecorder = LocationRecorder()
    @StateObject private var notificationMappingManager = NotificationMappingManager()
    @StateObject private var actionHistoryManager = ActionHistoryManager()
    @StateObject private var waterIntakeManager = WaterIntakeManager()

    var body: some Scene {
        WindowGroup {
            ConnectionView()
                .environmentObject(bleManager)
                .environmentObject(actionManager)
                .environmentObject(locationRecorder)
                .environmentObject(notificationMappingManager)
                .environmentObject(actionHistoryManager)
                .environmentObject(waterIntakeManager)
                .onAppear {
                    actionManager.locationRecorder = locationRecorder
                    actionManager.bleManager = bleManager
                    actionManager.historyManager = actionHistoryManager
                    actionManager.waterIntakeManager = waterIntakeManager
                    locationRecorder.onRecorded = { [weak bleManager] in
                        bleManager?.sendCommand(name: "vibrator_start", value: [150])
                    }

                    // 재연결 시 BLEManager 가 끊긴 시간 기준으로 자동 escalation:
                    //   60s+ → Tier 2 (ANCS 필터 재적용)
                    //   1h+  → Tier 2 + Tier 3 (CBCentralManager 재생성)
                    // BLEManager 가 NotificationMappingManager 를 직접 import 하지 않도록
                    // 클로저로 적용 책임 위임.
                    bleManager.onConnected = { [weak bleManager] in
                        guard let ble = bleManager else { return }
                        ble.log("연결 완료")
                    }
                    bleManager.notificationMappingApplier = { [weak notificationMappingManager, weak bleManager] in
                        guard let mgr = notificationMappingManager,
                              let ble = bleManager else { return }
                        mgr.applyToWatch(ble: ble)
                    }

                    // 백그라운드 sync 알림 수신 → BLE keepalive 실행
                    NotificationCenter.default.addObserver(
                        forName: .backgroundSyncRequested,
                        object: nil,
                        queue: .main
                    ) { [weak bleManager] _ in
                        bleManager?.performBackgroundSync()
                    }

                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
                }
                .onReceive(bleManager.$lastButtonEvent) { event in
                    guard let event = event else { return }
                    // 크라운 3초 홀드(코드 11)는 Nord에서 미동작 — 무시
                    if event.eventType == 11 { return }
                    actionManager.handleButtonEvent(button: event.button, event: event.eventType)
                }
        }
    }
}

// MARK: - AppDelegate (앱 종료 감지)

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        BackgroundSyncScheduler.shared.registerTask()
        return true
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // 앱 종료 시 로컬 알림 예약
        let content = UNMutableNotificationContent()
        content.title = "Keepnaby 연결 끊김"
        content.body = "앱이 종료되어 시계 연결이 끊겼습니다. 탭하여 앱을 다시 실행하세요."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "app_terminated", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
}
