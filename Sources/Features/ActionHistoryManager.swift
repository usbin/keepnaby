import Foundation

struct ActionHistoryEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let trigger: String     // e.g. "상단 1회 클릭", "확장입력 3 (0011)"
    let actionName: String  // e.g. "폰 찾기", "IFTTT: foo"

    init(id: UUID = UUID(), timestamp: Date = Date(), trigger: String, actionName: String) {
        self.id = id
        self.timestamp = timestamp
        self.trigger = trigger
        self.actionName = actionName
    }

    var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: timestamp)
    }

    var dateString: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: timestamp)
    }
}

final class ActionHistoryManager: ObservableObject {
    @Published private(set) var entries: [ActionHistoryEntry] = []

    private static let key = "action_history_v1"
    private static let maxEntries = 300

    init() {
        load()
    }

    func record(trigger: String, actionName: String) {
        let entry = ActionHistoryEntry(trigger: trigger, actionName: actionName)
        entries.insert(entry, at: 0)
        if entries.count > Self.maxEntries {
            entries = Array(entries.prefix(Self.maxEntries))
        }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode([ActionHistoryEntry].self, from: data) else { return }
        entries = decoded
    }
}
