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
}

// MARK: - 알림 앱 모델

struct NotificationApp: Codable, Identifiable, Hashable {
    let id: String
    var bundleIdPrefix: String
    var displayName: String
    var systemImage: String
    var category: AppCategory

    /// 펌웨어 호환: 번들 ID를 14자로 truncate (BLE 캡처에서 확인)
    var truncatedPrefix: String {
        String(bundleIdPrefix.prefix(14))
    }

    enum AppCategory: String, Codable, CaseIterable, Identifiable {
        case messaging = "메시징"
        case social = "소셜"
        case email = "이메일"
        case call = "전화"
        case productivity = "생산성"
        case entertainment = "엔터테인먼트"
        case other = "기타"
        case custom = "사용자 정의"

        var id: String { rawValue }
    }
}

// MARK: - 알림 슬롯

struct NotificationSlot: Codable, Identifiable {
    let id: Int              // 1, 2, 3
    var appIds: Set<String>  // NotificationApp.id 참조 (앱별 필터)
    var categories: Set<Int> // AncsCategory.rawValue (카테고리 필터)
    var enabled: Bool

    var positionName: String { "\(id)시 방향 (진동 \(id)회)" }

    var hasContent: Bool { !appIds.isEmpty || !categories.isEmpty }

    var combinedCategoryBitmask: Int {
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
    @Published var customApps: [NotificationApp] = []

    private static let slotsKey = "kronaby_app_slots_v2"
    private static let customAppsKey = "kronaby_custom_apps_v1"

    /// 큐레이션된 앱 목록 (BLE 캡처 기반 + 인기 앱)
    static let knownApps: [NotificationApp] = [
        // 메시징
        NotificationApp(id: "messages", bundleIdPrefix: "com.apple.MobileSMS", displayName: "메시지", systemImage: "message.fill", category: .messaging),
        NotificationApp(id: "kakaotalk", bundleIdPrefix: "com.iwilab.KakaoT", displayName: "카카오톡", systemImage: "bubble.left.fill", category: .messaging),
        NotificationApp(id: "line", bundleIdPrefix: "jp.naver.line", displayName: "LINE", systemImage: "bubble.left.fill", category: .messaging),
        NotificationApp(id: "whatsapp", bundleIdPrefix: "net.whatsapp.Whats", displayName: "WhatsApp", systemImage: "bubble.left.fill", category: .messaging),
        NotificationApp(id: "telegram", bundleIdPrefix: "ph.telegra.Telegr", displayName: "Telegram", systemImage: "paperplane.fill", category: .messaging),
        NotificationApp(id: "signal", bundleIdPrefix: "org.whispersyste", displayName: "Signal", systemImage: "lock.fill", category: .messaging),

        // 소셜
        NotificationApp(id: "instagram", bundleIdPrefix: "com.burbn.instagr", displayName: "Instagram", systemImage: "camera.fill", category: .social),
        NotificationApp(id: "twitter", bundleIdPrefix: "com.atebits.Twee", displayName: "X (Twitter)", systemImage: "at", category: .social),
        NotificationApp(id: "threads", bundleIdPrefix: "com.burbn.barcel", displayName: "Threads", systemImage: "at", category: .social),
        NotificationApp(id: "facebook", bundleIdPrefix: "com.facebook.Fac", displayName: "Facebook", systemImage: "person.2.fill", category: .social),
        NotificationApp(id: "fbmessenger", bundleIdPrefix: "com.facebook.Mes", displayName: "Messenger", systemImage: "bubble.left.and.bubble.right.fill", category: .social),
        NotificationApp(id: "discord", bundleIdPrefix: "com.hammerandchi", displayName: "Discord", systemImage: "headphones", category: .social),
        NotificationApp(id: "slack", bundleIdPrefix: "com.tinyspeck.ch", displayName: "Slack", systemImage: "number", category: .social),

        // 이메일
        NotificationApp(id: "mail", bundleIdPrefix: "com.apple.mobile", displayName: "메일", systemImage: "envelope.fill", category: .email),
        NotificationApp(id: "gmail", bundleIdPrefix: "com.google.Gmail", displayName: "Gmail", systemImage: "envelope.fill", category: .email),
        NotificationApp(id: "outlook", bundleIdPrefix: "com.microsoft.Of", displayName: "Outlook", systemImage: "envelope.fill", category: .email),
        NotificationApp(id: "naver_mail", bundleIdPrefix: "com.nhn.NID.mail", displayName: "네이버 메일", systemImage: "envelope.fill", category: .email),

        // 전화
        NotificationApp(id: "phone", bundleIdPrefix: "com.apple.mobile", displayName: "전화", systemImage: "phone.fill", category: .call),
        NotificationApp(id: "facetime", bundleIdPrefix: "com.apple.faceti", displayName: "FaceTime", systemImage: "video.fill", category: .call),

        // 생산성
        NotificationApp(id: "calendar", bundleIdPrefix: "com.apple.mobile", displayName: "캘린더", systemImage: "calendar", category: .productivity),
        NotificationApp(id: "reminders", bundleIdPrefix: "com.apple.Remind", displayName: "미리알림", systemImage: "checklist", category: .productivity),
        NotificationApp(id: "notion", bundleIdPrefix: "notion.id", displayName: "Notion", systemImage: "doc.text", category: .productivity),
        NotificationApp(id: "teams", bundleIdPrefix: "com.microsoft.sk", displayName: "Teams", systemImage: "person.3.fill", category: .productivity),

        // 엔터테인먼트
        NotificationApp(id: "youtube", bundleIdPrefix: "com.google.ios.y", displayName: "YouTube", systemImage: "play.rectangle.fill", category: .entertainment),
        NotificationApp(id: "netflix", bundleIdPrefix: "com.netflix.Netf", displayName: "Netflix", systemImage: "film", category: .entertainment),
        NotificationApp(id: "toss", bundleIdPrefix: "viva.republica.i", displayName: "토스", systemImage: "wonsign.circle.fill", category: .other),
        NotificationApp(id: "naver", bundleIdPrefix: "com.nhn.NaverSe", displayName: "네이버", systemImage: "globe", category: .other),
        NotificationApp(id: "coupang", bundleIdPrefix: "com.coupang.Coup", displayName: "쿠팡", systemImage: "cart.fill", category: .other),
        NotificationApp(id: "baemin", bundleIdPrefix: "com.woowahan.wo", displayName: "배달의민족", systemImage: "takeoutbag.and.cup.and.straw.fill", category: .other),
    ]

    /// 모든 앱 (큐레이션 + 커스텀)
    var allApps: [NotificationApp] {
        Self.knownApps + customApps
    }

    init() {
        load()
        if slots.isEmpty {
            slots = [
                NotificationSlot(id: 1, appIds: [], categories: [], enabled: false),
                NotificationSlot(id: 2, appIds: [], categories: [], enabled: false),
                NotificationSlot(id: 3, appIds: [], categories: [], enabled: false),
            ]
        }
    }

    // MARK: - 커스텀 앱

    func addCustomApp(bundleIdPrefix: String, displayName: String) {
        let id = "custom_\(UUID().uuidString.prefix(8))"
        let app = NotificationApp(
            id: id,
            bundleIdPrefix: bundleIdPrefix,
            displayName: displayName,
            systemImage: "app.fill",
            category: .custom
        )
        customApps.append(app)
        saveCustomApps()
    }

    func removeCustomApp(id: String) {
        customApps.removeAll { $0.id == id }
        for i in slots.indices {
            slots[i].appIds.remove(id)
        }
        saveCustomApps()
        save()
    }

    // MARK: - Apply

    func applyToWatch(ble: BLEManager) {
        var delay: Double = 0

        // 0. vibrator_config — 진동 패턴 정의
        ble.sendCommand(name: "vibrator_config", value: [8, 50, 25, 80, 25, 35, 25, 35, 25, 40, 25, 90])
        ble.sendCommand(name: "vibrator_config", value: [9, 31, 30, 61, 30, 110, 300, 31, 30, 61, 30, 110])
        ble.sendCommand(name: "vibrator_config", value: [10, 31, 30, 190, 300, 50, 30, 90, 300, 50, 30, 90])
        ble.log("vibrator_config 패턴 8/9/10 전송")
        delay += 0.5

        // 1. alert_assign
        var assignArray = [0, 0, 0]
        for slot in slots where slot.enabled && slot.hasContent {
            if slot.id >= 1 && slot.id <= 3 {
                assignArray[slot.id - 1] = 1
            }
        }
        let alarmSlot = UserDefaults.standard.integer(forKey: "kronaby_alarm_slot")
        if alarmSlot >= 1 && alarmSlot <= 3 {
            assignArray[alarmSlot - 1] = 1
        }
        ble.sendCommand(name: "alert_assign", value: assignArray)
        ble.log("alert_assign(\(assignArray))")
        delay += 0.5

        // 2. 기존 필터 삭제 (0~34)
        for i in 0...34 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                ble.sendCommand(name: "ancs_filter", value: [i])
            }
            delay += 0.1
        }
        ble.log("필터 삭제 (0~34)")
        delay += 0.5

        // 3. 슬롯별 필터 설정
        var filterIndex = 0
        for slot in slots where slot.enabled && slot.hasContent {
            let vibSlot = slot.id
            let capturedDelay = delay

            // alert 명령: 슬롯 활성화
            DispatchQueue.main.asyncAfter(deadline: .now() + capturedDelay) {
                ble.sendCommand(name: "alert", value: vibSlot)
                ble.log("alert(\(vibSlot))")
            }
            delay += 0.3

            // 3a. 카테고리 필터 (bitmask 방식)
            if !slot.categories.isEmpty {
                let idx = filterIndex
                let bitmask = slot.combinedCategoryBitmask
                let vib = vibSlot
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    ble.sendCommand(name: "ancs_filter", value: [
                        idx, bitmask, 255, "", vib
                    ] as [Any])
                    ble.log("ancs_filter[\(idx)]: 카테고리 bitmask=\(bitmask) → 진동 \(vib)")
                }
                filterIndex += 1
                delay += 0.3
            }

            // 3b. 앱별 필터 (번들 ID 방식)
            for appId in slot.appIds.sorted() {
                guard let app = allApps.first(where: { $0.id == appId }) else { continue }
                let idx = filterIndex
                let prefix = app.truncatedPrefix
                let vib = vibSlot
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    ble.sendCommand(name: "ancs_filter", value: [
                        idx, 0xFFFFFF, 0, prefix, vib
                    ] as [Any])
                    ble.log("ancs_filter[\(idx)]: \(prefix) → 진동 \(vib)")
                }
                filterIndex += 1
                delay += 0.3
            }
        }

        // 4. remote_data — 바늘 위치
        let remoteDelay = delay + 0.5
        for slot in slots where slot.enabled && slot.hasContent {
            let pos = slot.id
            DispatchQueue.main.asyncAfter(deadline: .now() + remoteDelay + Double(pos - 1) * 0.3) {
                ble.sendCommand(name: "remote_data", value: [10, 0, pos])
                ble.log("remote_data([10, 0, \(pos)])")
            }
        }
    }

    // MARK: - Persistence

    func save() {
        if let data = try? JSONEncoder().encode(slots) {
            UserDefaults.standard.set(data, forKey: Self.slotsKey)
        }
    }

    private func saveCustomApps() {
        if let data = try? JSONEncoder().encode(customApps) {
            UserDefaults.standard.set(data, forKey: Self.customAppsKey)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: Self.slotsKey),
           let decoded = try? JSONDecoder().decode([NotificationSlot].self, from: data) {
            slots = decoded
        }
        if let data = UserDefaults.standard.data(forKey: Self.customAppsKey),
           let decoded = try? JSONDecoder().decode([NotificationApp].self, from: data) {
            customApps = decoded
        }
    }

}
