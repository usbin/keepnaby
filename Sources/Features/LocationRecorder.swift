import CoreLocation
import UserNotifications
import UIKit

struct SavedLocation: Codable, Identifiable {
    let id: String
    let latitude: Double
    let longitude: Double
    let timestamp: Date
    var placeName: String

    var coordinateString: String {
        String(format: "%.5f, %.5f", latitude, longitude)
    }

    var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: timestamp)
    }
}

final class LocationRecorder: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var savedLocations: [SavedLocation] = []

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private static let storageKey = "saved_locations"

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        loadLocations()
        requestNotificationPermission()
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    private var lastRecordTime: Date = .distantPast

    func recordCurrentLocation() {
        // 3초 이내 중복 호출 방지
        let now = Date()
        guard now.timeIntervalSince(lastRecordTime) > 3.0 else { return }
        lastRecordTime = now
        requestPermission()
        manager.requestLocation()
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }

        // 같은 좌표 중복 저장 방지 (1초 이내)
        if let last = savedLocations.first,
           abs(last.timestamp.timeIntervalSinceNow) < 3.0 {
            return
        }

        let entryId = UUID().uuidString
        let entry = SavedLocation(
            id: entryId,
            latitude: loc.coordinate.latitude,
            longitude: loc.coordinate.longitude,
            timestamp: Date(),
            placeName: ""
        )
        savedLocations.insert(entry, at: 0)
        saveLocations()

        // Reverse geocode → 완료 후 알림
        geocoder.reverseGeocodeLocation(loc) { [weak self] placemarks, _ in
            guard let self else { return }
            let name: String
            if let pm = placemarks?.first {
                name = [pm.locality, pm.subLocality, pm.thoroughfare]
                    .compactMap { $0 }
                    .joined(separator: " ")
            } else {
                name = ""
            }
            let finalName = name.isEmpty ? entry.coordinateString : name
            if let idx = self.savedLocations.firstIndex(where: { $0.id == entryId }) {
                self.savedLocations[idx].placeName = finalName
                self.saveLocations()
            }
            self.sendNotification(title: "위치 저장됨", body: finalName)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        sendNotification(title: "위치 기록 실패", body: error.localizedDescription)
    }

    // MARK: - Delete

    func delete(at offsets: IndexSet) {
        savedLocations.remove(atOffsets: offsets)
        saveLocations()
    }

    func deleteByIDs(_ ids: Set<String>) {
        savedLocations.removeAll { ids.contains($0.id) }
        saveLocations()
    }

    func deleteAll() {
        savedLocations.removeAll()
        saveLocations()
    }

    // MARK: - Map

    func openInMap(_ location: SavedLocation) {
        let lat = location.latitude
        let lon = location.longitude

        // Try KakaoMap first
        if let kakao = URL(string: "kakaomap://look?p=\(lat),\(lon)"),
           UIApplication.shared.canOpenURL(kakao) {
            UIApplication.shared.open(kakao)
            return
        }

        // Fallback: Apple Maps
        if let apple = URL(string: "maps://?ll=\(lat),\(lon)&q=\(location.placeName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Pin")") {
            UIApplication.shared.open(apple)
        }
    }

    // MARK: - Persistence

    private func saveLocations() {
        if let data = try? JSONEncoder().encode(savedLocations) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    private func loadLocations() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([SavedLocation].self, from: data) {
            savedLocations = decoded
        }
    }

    // MARK: - Notifications

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func sendNotification(entry: SavedLocation) {
        sendNotification(title: "위치 저장됨", body: "\(entry.placeName)\n\(entry.coordinateString)")
    }

    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
