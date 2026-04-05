import Foundation

// MARK: - ANCS 카테고리

enum AncsCategory: Int, Codable, CaseIterable, Identifiable {
    case other = 0
    case incomingCall = 1
    case missedCall = 2
    case voicemail = 3
    case social = 4
    case schedule = 5
    case email = 6
    case news = 7
    case healthFitness = 8
    case businessFinance = 9
    case location = 10
    case entertainment = 11

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .other: return "기타"
        case .incomingCall: return "수신 전화"
        case .missedCall: return "부재중 전화"
        case .voicemail: return "음성 메일"
        case .social: return "소셜 미디어"
        case .schedule: return "일정"
        case .email: return "이메일"
        case .news: return "뉴스"
        case .healthFitness: return "건강/피트니스"
        case .businessFinance: return "비즈니스/금융"
        case .location: return "위치"
        case .entertainment: return "엔터테인먼트"
        }
    }

    var systemImage: String {
        switch self {
        case .other: return "app.badge.fill"
        case .incomingCall: return "phone.fill"
        case .missedCall: return "phone.arrow.down.left"
        case .voicemail: return "recordingtape"
        case .social: return "person.2.fill"
        case .schedule: return "calendar"
        case .email: return "envelope.fill"
        case .news: return "newspaper.fill"
        case .healthFitness: return "heart.fill"
        case .businessFinance: return "chart.line.uptrend.xyaxis"
        case .location: return "location.fill"
        case .entertainment: return "film"
        }
    }

    var bitmask: Int { 1 << (rawValue + 8) }
    static var allBitmask: Int { 0xFFFFFF }
}

// MARK: - 카테고리 슬롯 (1~3)

struct NotificationSlot: Codable, Identifiable {
    let id: Int              // 1, 2, 3
    var categories: Set<Int>
    var enabled: Bool

    var positionName: String { "\(id)시 방향 (진동 \(id)회)" }

    var combinedBitmask: Int {
        var mask = 0
        for catRaw in categories {
            if let cat = AncsCategory(rawValue: catRaw) {
                mask |= cat.bitmask
            }
        }
        return mask
    }

    func hasCategory(_ cat: AncsCategory) -> Bool {
        categories.contains(cat.rawValue)
    }

    mutating func toggleCategory(_ cat: AncsCategory) {
        if categories.contains(cat.rawValue) {
            categories.remove(cat.rawValue)
        } else {
            categories.insert(cat.rawValue)
        }
    }
}

// MARK: - Manager

final class NotificationMappingManager: ObservableObject {
    @Published var slots: [NotificationSlot] = []

    private static let slotsKey = "kronaby_ancs_slots_v5"

    init() {
        load()
        if slots.isEmpty {
            slots = [
                NotificationSlot(id: 1, categories: [1, 2], enabled: false),
                NotificationSlot(id: 2, categories: [4, 6], enabled: false),
                NotificationSlot(id: 3, categories: [0], enabled: false),
            ]
        }
    }

    // MARK: - Apply

    func applyToWatch(ble: BLEManager) {
        var delay: Double = 0

        // 카테고리 슬롯 (인덱스 1~3) — 삭제 없이 바로 설정
        for slot in slots {
            let idx = slot.id
            if slot.enabled && !slot.categories.isEmpty {
                let bitmask = slot.combinedBitmask
                let vib = slot.id
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    ble.sendCommand(name: "ancs_filter", value: [
                        idx, bitmask, 255, "", vib
                    ] as [Any])
                    ble.log("카테고리[\(idx)]: bitmask=\(bitmask), vib=\(vib)")
                }
            } else {
                // 비활성 슬롯은 삭제
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    ble.sendCommand(name: "ancs_filter", value: [idx])
                    ble.log("카테고리[\(idx)]: 삭제")
                }
            }
            delay += 0.3
        }
    }

    // MARK: - Persistence

    func save() {
        if let data = try? JSONEncoder().encode(slots) {
            UserDefaults.standard.set(data, forKey: Self.slotsKey)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: Self.slotsKey),
           let decoded = try? JSONDecoder().decode([NotificationSlot].self, from: data) {
            slots = decoded
        }
    }

}
