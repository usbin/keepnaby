import SwiftUI

@main
struct KronabyApp: App {
    @StateObject private var bleManager = BLEManager()
    @StateObject private var actionManager = ButtonActionManager()

    var body: some Scene {
        WindowGroup {
            ConnectionView()
                .environmentObject(bleManager)
                .environmentObject(actionManager)
                .onReceive(bleManager.$lastButtonEvent) { event in
                    guard let event = event else { return }
                    if event.eventType == 11 {
                        // Crown 3-sec hold → Find My Phone (always)
                        actionManager.handleFindMyPhone()
                    } else {
                        actionManager.handleButtonEvent(button: event.button, event: event.eventType)
                    }
                }
        }
    }
}
