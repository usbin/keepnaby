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

    var body: some Scene {
        WindowGroup {
            ConnectionView()
                .environmentObject(bleManager)
                .environmentObject(actionManager)
                .environmentObject(locationRecorder)
                .environmentObject(notificationMappingManager)
                .environmentObject(actionHistoryManager)
                .onAppear {
                    actionManager.locationRecorder = locationRecorder
                    actionManager.bleManager = bleManager
                    actionManager.historyManager = actionHistoryManager
                    locationRecorder.onRecorded = { [weak bleManager] in
                        bleManager?.sendCommand(name: "vibrator_start", value: [150])
                    }

                    // 재연결 시 최소한의 명령만 전송 (설정은 펌웨어에 저장됨)
                    bleManager.onConnected = { [weak bleManager] in
                        guard let ble = bleManager else { return }
                        ble.log("연결 완료 — 최소 초기화만 전송")
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
