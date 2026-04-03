import SwiftUI

enum ComplicationMode: Int, CaseIterable, Identifiable {
    case none = 0
    case time = 1
    case date = 3
    case weatherTemp = 4
    case steps = 5
    case battery = 6
    case dateWeekday = 7
    case dateRadial = 8
    case seconds = 10
    case worldtime = 15
    case alarm = 16

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .none: return "없음"
        case .time: return "시:분"
        case .date: return "날짜"
        case .weatherTemp: return "날씨 온도"
        case .steps: return "만보기"
        case .battery: return "배터리"
        case .dateWeekday: return "날짜 + 요일"
        case .dateRadial: return "날짜 (방사형)"
        case .seconds: return "초"
        case .worldtime: return "세계시간"
        case .alarm: return "알람"
        }
    }
}

struct ComplicationsView: View {
    @EnvironmentObject var ble: BLEManager
    @State private var mainMode: ComplicationMode = .date
    @State private var saved = false

    private static let savedKey = "kronaby_complication_main"

    var body: some View {
        NavigationStack {
            Form {
                Section("크라운 클릭 시 표시") {
                    Picker("기능", selection: $mainMode) {
                        ForEach(ComplicationMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.inline)
                }

                Section {
                    Text("크라운을 클릭하면 시침과 분침이 이동하여\n선택한 정보를 표시한 후 원래 위치로 돌아갑니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button("시계에 적용") {
                        apply()
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)

                    if saved {
                        Text("적용 완료!")
                            .foregroundStyle(.green)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("크라운 설정")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                let raw = UserDefaults.standard.integer(forKey: Self.savedKey)
                mainMode = ComplicationMode(rawValue: raw) ?? .date
            }
        }
    }

    private func apply() {
        ble.sendCommand(name: "complications", value: [mainMode.rawValue])
        UserDefaults.standard.set(mainMode.rawValue, forKey: Self.savedKey)
        saved = true
        ble.log("complications 설정: \(mainMode.displayName) (\(mainMode.rawValue))")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saved = false }
    }
}
