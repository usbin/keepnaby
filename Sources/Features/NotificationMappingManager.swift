import Foundation

// MARK: - ANCS 카테고리 (Kronaby 펌웨어 기준)

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
}

// MARK: - 알림 슬롯 (3개 위치)

struct NotificationSlot: Codable, Identifiable {
    let id: Int              // 1, 2, 3
    var categories: Set<Int> // AncsCategory.rawValue set
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

    private static let storageKey = "kronaby_ancs_slots_v4"

    init() {
        load()
        if slots.isEmpty {
            slots = [
                NotificationSlot(id: 1, categories: [1, 2], enabled: false),   // 수신전화, 부재중
                NotificationSlot(id: 2, categories: [4, 6], enabled: false),   // 소셜, 이메일
                NotificationSlot(id: 3, categories: [0], enabled: false),      // 기타
            ]
        }
    }

    // MARK: - Apply to Watch

    func applyToWatch(ble: BLEManager) {
        var delay: Double = 0

        // 1. 기존 필터 삭제 (인덱스 0~3)
        for i in 0...3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                ble.sendCommand(name: "ancs_filter", value: [i])
            }
            delay += 0.1
        }

        delay += 0.3

        // 2. 활성 슬롯 전송
        for slot in slots where slot.enabled && !slot.categories.isEmpty {
            let idx = slot.id
            let bitmask = slot.combinedBitmask
            let vibration = slot.id // 1, 2, 3

            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                ble.sendCommand(name: "ancs_filter", value: [
                    idx, bitmask, 255, "", vibration
                ] as [Any])
                ble.log("ancs_filter[\(idx)]: bitmask=\(bitmask), vib=\(vibration)")
            }
            delay += 0.3
        }
    }

    // MARK: - Persistence

    func save() {
        if let data = try? JSONEncoder().encode(slots) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([NotificationSlot].self, from: data) {
            slots = decoded
        }
    }
}