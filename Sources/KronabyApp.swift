import SwiftUI
import UserNotifications

@main
struct KronabyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var bleManager = BLEManager()
    @StateObject private var actionManager = ButtonActionManager()
    @StateObject private var locationRecorder = LocationRecorder()
    @StateObject private var notificationMappingManager = NotificationMappingManager()

    var body: some Scene {
        WindowGroup {
            ConnectionView()
                .environmentObject(bleManager)
                .environmentObject(actionManager)
                .environmentObject(locationRecorder)
                .environmentObject(notificationMappingManager)
                .onAppear {
                    actionManager.locationRecorder = locationRecorder
                    locationRecorder.onRecorded = { [weak bleManager] in
                        bleManager?.sendCommand(name: "vibrator_start", value: [150])
                    }
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
                }
                .onReceive(bleManager.$lastButtonEvent) { event in
                    guard let event = event else { return }
                    if event.eventType == 11 {
                        actionManager.handleFindMyPhone()
                    } else {
                        actionManager.handleButtonEvent(button: event.button, event: event.eventType)
                    }
                }
        }
    }
}

// MARK: - AppDelegate (앱 종료 감지)

class AppDelegate: NSObject, UIApplicationDelegate {
    func applicationWillTerminate(_ application: UIApplication) {
        // 앱 종료 시 로컬 알림 예약
        let content = UNMutableNotificationContent()
        content.title = "Kronaby 연결 끊김"
        content.body = "앱이 종료되어 시계 연결이 끊겼습니다. 탭하여 앱을 다시 실행하세요."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "app_terminated", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
}
