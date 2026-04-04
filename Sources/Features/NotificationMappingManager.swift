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

    // ANCS 카테고리 비트마스크: 1 << (rawValue + 8)
    var bitmask: Int {
        1 << (rawValue + 8)
    }

    // 모든 카테고리 비트마스크
    static var allBitmask: Int { 0xFFFFFF }
}

enum VibrationPattern: Int, Codable, CaseIterable, Identifiable {
    case single = 1
    case double = 2
    case triple = 3

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .single: return "진동 1회"
        case .double: return "진동 2회"
        case .triple: return "진동 3회"
        }
    }
}

// MARK: - 필터 설정

struct NotificationFilter: Codable, Equatable, Identifiable {
    var id: Int             // 필터 인덱스 (0~34), 바늘 위치와 연관 가능
    var category: AncsCategory?  // nil = 모든 알림
    var vibration: VibrationPattern
    var position: Int       // 시계 숫자 위치 (1~12)
    var enabled: Bool
    var isAllNotifications: Bool  // 모든 알림 필터 여부

    var displayName: String {
        if isAllNotifications { return "모든 알림" }
        return category?.displayName ?? "알 수 없음"
    }

    var systemImage: String {
        if isAllNotifications { return "bell.badge.fill" }
        return category?.systemImage ?? "questionmark"
    }

    var bitmask: Int {
        if isAllNotifications { return AncsCategory.allBitmask }
        return category?.bitmask ?? 0
    }
}

// MARK: - Manager

final class NotificationMappingManager: ObservableObject {
    @Published var filters: [NotificationFilter] = []

    private static let storageKey = "kronaby_ancs_filters_v2"

    init() {
        load()
        if filters.isEmpty {
            filters = [
                NotificationFilter(id: 0, category: nil, vibration: .single, position: 11, enabled: false, isAllNotifications: true),
                NotificationFilter(id: 1, category: .incomingCall, vibration: .double, position: 12, enabled: false, isAllNotifications: false),
                NotificationFilter(id: 2, category: .missedCall, vibration: .single, position: 1, enabled: false, isAllNotifications: false),
                NotificationFilter(id: 3, category: .social, vibration: .single, position: 2, enabled: false, isAllNotifications: false),
                NotificationFilter(id: 4, category: .email, vibration: .single, position: 3, enabled: false, isAllNotifications: false),
                NotificationFilter(id: 5, category: .schedule, vibration: .single, position: 4, enabled: false, isAllNotifications: false),
                NotificationFilter(id: 6, category: .news, vibration: .single, position: 5, enabled: false, isAllNotifications: false),
                NotificationFilter(id: 7, category: .entertainment, vibration: .single, position: 6, enabled: false, isAllNotifications: false),
                NotificationFilter(id: 8, category: .other, vibration: .single, position: 7, enabled: false, isAllNotifications: false),
            ]
        }
    }

    // MARK: - Apply to Watch

    func applyToWatch(ble: BLEManager) {
        for filter in filters {
            if filter.enabled {
                // 활성 필터: [index, categoryBitmask, attribute(255=all), "", vibrationPattern]
                // index가 바늘 위치를 결정할 수 있음 (테스트 필요)
                let filterIndex = filter.position  // 위치값을 인덱스로 사용
                ble.sendCommand(name: "ancs_filter", value: [
                    filterIndex,
                    filter.bitmask,
                    255,
                    "",
                    filter.vibration.rawValue
                ] as [Any])
                ble.log("ancs_filter[\(filterIndex)]: \(filter.displayName) → 위치 \(filter.position), \(filter.vibration.displayName)")
            } else {
                // 비활성 필터: [index] (삭제)
                ble.sendCommand(name: "ancs_filter", value: [filter.position])
                ble.log("ancs_filter[\(filter.position)]: 삭제")
            }
        }
    }

    // MARK: - Persistence

    func save() {
        if let data = try? JSONEncoder().encode(filters) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([NotificationFilter].self, from: data) {
            filters = decoded
        }
    }
}