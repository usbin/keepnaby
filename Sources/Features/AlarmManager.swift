import Foundation

struct WatchAlarm: Codable, Identifiable, Equatable {
    var id: Int          // 1~8
    var hour: Int        // 0~23
    var minute: Int      // 0~59
    var enabled: Bool
    var days: Set<Int>   // 1=월, 2=화, 3=수, 4=목, 5=금, 6=토, 7=일 (ISO)

    var timeString: String {
        String(format: "%02d:%02d", hour, minute)
    }

    var daysString: String {
        if days.count == 7 { return "매일" }
        if days.isEmpty { return "반복 없음" }
        let names = ["", "월", "화", "수", "목", "금", "토", "일"]
        return days.sorted().map { names[$0] }.joined(separator: " ")
    }

    // 요일 비트마스크: bit1=월, bit2=화, ..., bit7=일
    var daysBitmask: Int {
        var mask = 0
        for day in days {
            mask |= (1 << day)
        }
        return mask
    }

    // config byte: (daysBitmask << 1) | enabled
    // 실제: bits 1-7 = days, bit 0 = enabled
    var configByte: UInt8 {
        var config = daysBitmask
        if enabled { config |= 1 }
        return UInt8(config & 0xFF)
    }

    // 13바이트 바이너리 인코딩
    func encode() -> Data {
        var data = Data(count: 13)

        // ID (4 bytes, little-endian)
        let idLE = UInt32(id).littleEndian
        withUnsafeBytes(of: idLE) { data.replaceSubrange(0..<4, with: $0) }

        // Last Modified (4 bytes, little-endian)
        let timestamp = UInt32(Date().timeIntervalSince1970)
        let tsLE = timestamp.littleEndian
        withUnsafeBytes(of: tsLE) { data.replaceSubrange(4..<8, with: $0) }

        // Hour, Minute
        data[8] = UInt8(hour)
        data[9] = UInt8(minute)

        // Reserved (2 bytes)
        data[10] = 0
        data[11] = 0

        // Config byte
        data[12] = configByte

        return data
    }
}

final class AlarmManager: ObservableObject {
    @Published var alarms: [WatchAlarm] = []

    private static let storageKey = "kronaby_alarms"
    static let maxAlarms = 8

    init() {
        load()
        if alarms.isEmpty {
            // 빈 알람 슬롯 1개
            alarms = [
                WatchAlarm(id: 1, hour: 7, minute: 0, enabled: false, days: [1, 2, 3, 4, 5])
            ]
        }
    }

    func addAlarm() {
        guard alarms.count < Self.maxAlarms else { return }
        let newId = (alarms.map(\.id).max() ?? 0) + 1
        alarms.append(WatchAlarm(id: newId, hour: 7, minute: 0, enabled: false, days: []))
        save()
    }

    func removeAlarm(at offsets: IndexSet) {
        alarms.remove(atOffsets: offsets)
        save()
    }

    func applyToWatch(ble: BLEManager) {
        // 헤더: [version(2), count(1), reserved(1)] + 알람 데이터
        var payload = Data()

        // Version (uint16 LE) = 1
        var version = UInt16(1).littleEndian
        payload.append(Data(bytes: &version, count: 2))

        // Number of alarms
        payload.append(UInt8(alarms.count))

        // Reserved
        payload.append(0)

        // 각 알람 13바이트
        for alarm in alarms {
            payload.append(alarm.encode())
        }

        // alarm 명령으로 raw bytes 전송
        ble.sendRawCommand(name: "alarm", data: payload)
        ble.log("alarm 전송: \(alarms.count)개 알람")
    }

    func save() {
        if let data = try? JSONEncoder().encode(alarms) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([WatchAlarm].self, from: data) {
            alarms = decoded
        }
    }
}