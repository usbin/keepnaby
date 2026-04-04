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

// MARK: - 앱 필터

struct AppFilter: Codable, Identifiable, Equatable {
    var id: String  // bundleId
    var name: String
    var bundleId: String
    var vibration: Int  // 1~3 (위치 = 진동횟수)
    var enabled: Bool
}

// MARK: - Manager

final class NotificationMappingManager: ObservableObject {
    @Published var slots: [NotificationSlot] = []
    @Published var appFilters: [AppFilter] = []

    private static let slotsKey = "kronaby_ancs_slots_v5"
    private static let appFiltersKey = "kronaby_ancs_apps_v1"

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

    func addAppFilter(bundleId: String, name: String, vibration: Int = 1) {
        guard !appFilters.contains(where: { $0.bundleId == bundleId }) else { return }
        appFilters.append(AppFilter(
            id: bundleId, name: name, bundleId: bundleId,
            vibration: vibration, enabled: true
        ))
        save()
    }

    func removeAppFilter(id: String) {
        appFilters.removeAll { $0.id == id }
        save()
    }

    // MARK: - Apply

    func applyToWatch(ble: BLEManager) {
        var delay: Double = 0

        // 1. 기존 필터 삭제 (인덱스 0~20)
        for i in 0...20 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                ble.sendCommand(name: "ancs_filter", value: [i])
            }
            delay += 0.05
        }
        ble.log("필터 삭제 (0~20)")

        delay += 0.5

        // 2. 카테고리 슬롯 (인덱스 1~3)
        for slot in slots where slot.enabled && !slot.categories.isEmpty {
            let idx = slot.id
            let bitmask = slot.combinedBitmask
            let vib = slot.id

            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                ble.sendCommand(name: "ancs_filter", value: [
                    idx, bitmask, 255, "", vib
                ] as [Any])
                ble.log("카테고리[\(idx)]: bitmask=\(bitmask), vib=\(vib)")
            }
            delay += 0.3
        }

        // 3. 앱 필터 (인덱스 10~)
        for (i, filter) in appFilters.enumerated() where filter.enabled {
            let idx = 10 + i
            let vib = filter.vibration

            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                ble.sendCommand(name: "ancs_filter", value: [
                    idx, AncsCategory.allBitmask, 0, filter.bundleId, vib
                ] as [Any])
                ble.log("앱필터[\(idx)]: \(filter.name) → vib=\(vib)")
            }
            delay += 0.3
        }
    }

    // MARK: - Persistence

    func save() {
        if let data = try? JSONEncoder().encode(slots) {
            UserDefaults.standard.set(data, forKey: Self.slotsKey)
        }
        if let data = try? JSONEncoder().encode(appFilters) {
            UserDefaults.standard.set(data, forKey: Self.appFiltersKey)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: Self.slotsKey),
           let decoded = try? JSONDecoder().decode([NotificationSlot].self, from: data) {
            slots = decoded
        }
        if let data = UserDefaults.standard.data(forKey: Self.appFiltersKey),
           let decoded = try? JSONDecoder().decode([AppFilter].self, from: data) {
            appFilters = decoded
        }
    }

    // 자주 쓰는 앱
    static let commonApps: [(name: String, bundleId: String)] = [
        ("카카오톡", "com.iwilab.KakaoTalk"),
        ("라인", "jp.naver.line"),
        ("텔레그램", "ph.telegra.Telegraph"),
        ("왓츠앱", "net.whatsapp.WhatsApp"),
        ("인스타그램", "com.burbn.instagram"),
        ("Outlook", "com.microsoft.Office.Outlook"),
        ("Gmail", "com.google.Gmail"),
        ("슬랙", "com.tinyspeck.chatlyio"),
        ("디스코드", "com.hammerandchisel.discord"),
        ("X (Twitter)", "com.atebits.Tweetie2"),
        ("유튜브", "com.google.ios.youtube"),
    ]
}
