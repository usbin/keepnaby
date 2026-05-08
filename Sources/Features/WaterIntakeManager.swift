import Foundation

struct WaterIntakeRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let amountML: Int

    init(id: UUID = UUID(), timestamp: Date = Date(), amountML: Int) {
        self.id = id
        self.timestamp = timestamp
        self.amountML = amountML
    }

    var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: timestamp)
    }
}

final class WaterIntakeManager: ObservableObject {
    @Published private(set) var records: [WaterIntakeRecord] = []
    @Published var standardAmountML: Int = 200 {
        didSet { UserDefaults.standard.set(standardAmountML, forKey: Self.standardKey) }
    }
    @Published var dailyGoalML: Int = 2000 {
        didSet { UserDefaults.standard.set(dailyGoalML, forKey: Self.goalKey) }
    }

    private static let recordsKey = "kronaby_water_records_v1"
    private static let standardKey = "kronaby_water_standard_amount_v1"
    private static let goalKey = "kronaby_water_daily_goal_v1"
    private static let retentionDays = 90

    init() {
        load()
    }

    // MARK: - Mutations

    func recordDrink() {
        recordCustom(amountML: standardAmountML)
    }

    func recordCustom(amountML: Int) {
        guard amountML > 0 else { return }
        let entry = WaterIntakeRecord(amountML: amountML)
        records.insert(entry, at: 0)
        pruneOldRecords()
        save()
    }

    func deleteRecord(id: UUID) {
        records.removeAll { $0.id == id }
        save()
    }

    func deleteRecords(ids: [UUID]) {
        let set = Set(ids)
        records.removeAll { set.contains($0.id) }
        save()
    }

    // MARK: - Queries

    func todayTotal() -> Int {
        let cal = Calendar.current
        return records
            .filter { cal.isDateInToday($0.timestamp) }
            .reduce(0) { $0 + $1.amountML }
    }

    func todayRecords() -> [WaterIntakeRecord] {
        let cal = Calendar.current
        return records.filter { cal.isDateInToday($0.timestamp) }
    }

    func progressFraction() -> Double {
        guard dailyGoalML > 0 else { return 0 }
        return Double(todayTotal()) / Double(dailyGoalML)
    }

    /// 최근 `lastDays` 일의 (일자, 합계) 배열 — 오늘 포함, 일자 내림차순.
    func dailyTotals(lastDays: Int) -> [(date: Date, total: Int)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var result: [(Date, Int)] = []
        for offset in 0..<lastDays {
            guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            let total = records
                .filter { cal.isDate($0.timestamp, inSameDayAs: day) }
                .reduce(0) { $0 + $1.amountML }
            result.append((day, total))
        }
        return result
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: Self.recordsKey)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: Self.recordsKey),
           let decoded = try? JSONDecoder().decode([WaterIntakeRecord].self, from: data) {
            records = decoded
            pruneOldRecords()
        }
        let savedStandard = UserDefaults.standard.integer(forKey: Self.standardKey)
        if savedStandard > 0 { standardAmountML = savedStandard }
        let savedGoal = UserDefaults.standard.integer(forKey: Self.goalKey)
        if savedGoal > 0 { dailyGoalML = savedGoal }
    }

    private func pruneOldRecords() {
        let cal = Calendar.current
        guard let cutoff = cal.date(byAdding: .day, value: -Self.retentionDays, to: Date()) else { return }
        records.removeAll { $0.timestamp < cutoff }
    }
}
