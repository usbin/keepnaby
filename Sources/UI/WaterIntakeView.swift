import SwiftUI

struct WaterIntakeView: View {
    @EnvironmentObject var manager: WaterIntakeManager

    var body: some View {
        Form {
            Section("오늘") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(manager.todayTotal())ml")
                            .font(.system(size: 32, weight: .semibold, design: .rounded))
                        Text("/ \(manager.dailyGoalML)ml")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(percentText)
                            .font(.subheadline.bold())
                            .foregroundStyle(progressColor)
                    }
                    ProgressView(value: clampedProgress)
                        .tint(progressColor)
                }
                .padding(.vertical, 2)

                Button {
                    manager.recordDrink()
                } label: {
                    Label("물 한 잔 (\(manager.standardAmountML)ml)", systemImage: "drop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }

            Section("설정") {
                Stepper(
                    "1회 표준량: \(manager.standardAmountML)ml",
                    value: $manager.standardAmountML,
                    in: 50...1000,
                    step: 50
                )
                Stepper(
                    "일일 목표: \(manager.dailyGoalML)ml",
                    value: $manager.dailyGoalML,
                    in: 500...5000,
                    step: 100
                )
                Text("시계 버튼 또는 모스 명령에 '물 섭취 기록' 액션을 매핑하면 한 번 누를 때마다 표준량만큼 기록됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                if todayRecords.isEmpty {
                    Text("오늘 기록 없음")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(todayRecords) { rec in
                        HStack {
                            Image(systemName: "drop.fill")
                                .foregroundStyle(.blue)
                            Text(rec.timeString)
                            Spacer()
                            Text("\(rec.amountML)ml")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete(perform: deleteToday)
                }
            } header: {
                Text("오늘 기록")
            } footer: {
                if !todayRecords.isEmpty {
                    Text("왼쪽으로 밀어서 잘못된 기록을 삭제할 수 있습니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("최근 7일") {
                ForEach(weeklyTotals, id: \.date) { item in
                    HStack {
                        Text(weekdayLabel(item.date))
                            .frame(width: 80, alignment: .leading)
                        ProgressView(
                            value: min(Double(item.total) / Double(max(manager.dailyGoalML, 1)), 1.0)
                        )
                        Text("\(item.total)ml")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 70, alignment: .trailing)
                    }
                }
            }
        }
        .navigationTitle("물 섭취 기록")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Helpers

    private var todayRecords: [WaterIntakeRecord] {
        manager.todayRecords()
    }

    private var weeklyTotals: [(date: Date, total: Int)] {
        manager.dailyTotals(lastDays: 7)
    }

    private var clampedProgress: Double {
        min(manager.progressFraction(), 1.0)
    }

    private var percentText: String {
        let pct = Int(manager.progressFraction() * 100)
        return "\(pct)%"
    }

    private var progressColor: Color {
        let frac = manager.progressFraction()
        if frac >= 1.0 { return .green }
        if frac >= 0.5 { return .blue }
        return .cyan
    }

    private func deleteToday(at offsets: IndexSet) {
        let ids = offsets.compactMap { idx -> UUID? in
            guard idx < todayRecords.count else { return nil }
            return todayRecords[idx].id
        }
        manager.deleteRecords(ids: ids)
    }

    private func weekdayLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "오늘" }
        if cal.isDateInYesterday(date) { return "어제" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M/d (E)"
        return f.string(from: date)
    }
}
