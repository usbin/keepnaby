import SwiftUI

// MARK: - 뮤트/카메라 트리거

enum TriggerValue: Int, CaseIterable, Identifiable {
    case none = 0
    case camera = 1
    case mediaControl = 2
    case mute = 3

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .none: return "없음"
        case .camera: return "카메라"
        case .mediaControl: return "미디어 제어"
        case .mute: return "음소거"
        }
    }
}

struct WatchSettingsView: View {
    @EnvironmentObject var ble: BLEManager

    // Triggers
    @State private var topTrigger: TriggerValue = .none
    @State private var bottomTrigger: TriggerValue = .none

    // DND
    @State private var dndEnabled = false
    @State private var dndStartHour = 22
    @State private var dndStartMin = 0
    @State private var dndEndHour = 7
    @State private var dndEndMin = 0

    // World Time
    @State private var worldTimeHour = 0
    @State private var worldTimeMin = 0

    // Vibration
    @State private var vibStrength: Int = 0  // 0=normal, 1=stronger

    @State private var applied = false

    private static let triggerTopKey = "kronaby_trigger_top"
    private static let triggerBottomKey = "kronaby_trigger_bottom"
    private static let dndEnabledKey = "kronaby_dnd_enabled"
    private static let dndStartHKey = "kronaby_dnd_start_h"
    private static let dndStartMKey = "kronaby_dnd_start_m"
    private static let dndEndHKey = "kronaby_dnd_end_h"
    private static let dndEndMKey = "kronaby_dnd_end_m"
    private static let worldTimeHKey = "kronaby_wt_hour"
    private static let worldTimeMKey = "kronaby_wt_min"
    private static let vibStrengthKey = "kronaby_vib_strength"

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - HID 트리거
                Section("HID 트리거 (하드웨어 기능)") {
                    Picker("상단 버튼", selection: $topTrigger) {
                        ForEach(TriggerValue.allCases) { val in
                            Text(val.displayName).tag(val)
                        }
                    }
                    Picker("하단 버튼", selection: $bottomTrigger) {
                        ForEach(TriggerValue.allCases) { val in
                            Text(val.displayName).tag(val)
                        }
                    }
                    Text("카메라/음소거는 BLE HID로 동작합니다.\n버튼 매핑의 앱 액션과 별개로 작동합니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // MARK: - 방해금지
                Section("방해금지 (DND)") {
                    Toggle("방해금지 활성화", isOn: $dndEnabled)

                    if dndEnabled {
                        HStack {
                            Text("시작")
                            Spacer()
                            Picker("시", selection: $dndStartHour) {
                                ForEach(0..<24, id: \.self) { Text("\($0)시") }
                            }
                            .pickerStyle(.menu)
                            Picker("분", selection: $dndStartMin) {
                                ForEach([0, 15, 30, 45], id: \.self) { Text(String(format: "%02d분", $0)) }
                            }
                            .pickerStyle(.menu)
                        }
                        HStack {
                            Text("종료")
                            Spacer()
                            Picker("시", selection: $dndEndHour) {
                                ForEach(0..<24, id: \.self) { Text("\($0)시") }
                            }
                            .pickerStyle(.menu)
                            Picker("분", selection: $dndEndMin) {
                                ForEach([0, 15, 30, 45], id: \.self) { Text(String(format: "%02d분", $0)) }
                            }
                            .pickerStyle(.menu)
                        }
                    }
                }

                // MARK: - 세계시간
                Section("세계시간 (2nd Timezone)") {
                    HStack {
                        Text("UTC 오프셋")
                        Spacer()
                        Picker("시", selection: $worldTimeHour) {
                            ForEach(-12...14, id: \.self) { h in
                                Text("\(h >= 0 ? "+" : "")\(h)시간").tag(h)
                            }
                        }
                        .pickerStyle(.menu)
                        Picker("분", selection: $worldTimeMin) {
                            ForEach([0, 30, 45], id: \.self) { m in
                                Text("\(m)분").tag(m)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    Text("시계의 세컨드 타임존을 설정합니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // MARK: - 진동 세기
                Section("진동 세기") {
                    Picker("세기", selection: $vibStrength) {
                        Text("일반").tag(0)
                        Text("강하게").tag(1)
                    }
                    .pickerStyle(.segmented)
                    Text("일반: 짧은 진동 / 강하게: 긴 진동 (더 강하게 느껴짐)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // MARK: - 적용
                Section {
                    Button("시계에 적용") {
                        applyAll()
                    }
                    .frame(maxWidth: .infinity)

                    if applied {
                        Text("적용 완료!")
                            .foregroundStyle(.green)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("시계 설정")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { loadSettings() }
        }
    }

    private func applyAll() {
        // Triggers
        ble.sendCommand(name: "triggers", value: [topTrigger.rawValue, bottomTrigger.rawValue])
        ble.log("triggers: [\(topTrigger.displayName), \(bottomTrigger.displayName)]")

        // DND
        ble.sendCommand(name: "stillness", value: [
            dndEnabled ? 1 : 0, dndStartHour, dndStartMin, dndEndHour, dndEndMin
        ])
        ble.log("DND: \(dndEnabled ? "ON" : "OFF") \(dndStartHour):\(String(format: "%02d", dndStartMin))~\(dndEndHour):\(String(format: "%02d", dndEndMin))")

        // World Time (timezone2)
        ble.sendCommand(name: "timezone2", value: [worldTimeHour, worldTimeMin])
        ble.log("timezone2: UTC\(worldTimeHour >= 0 ? "+" : "")\(worldTimeHour):\(String(format: "%02d", worldTimeMin))")

        // Vibration strength
        if vibStrength == 1 {
            // Stronger: 600ms single pulse
            ble.sendCommand(name: "vibrator_config", value: [8, 600])
        } else {
            // Normal: 150ms single pulse
            ble.sendCommand(name: "vibrator_config", value: [8, 150])
        }
        ble.log("vibrator_config: \(vibStrength == 1 ? "강하게(600ms)" : "일반(150ms)")")

        saveSettings()
        applied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { applied = false }
    }

    private func saveSettings() {
        UserDefaults.standard.set(topTrigger.rawValue, forKey: Self.triggerTopKey)
        UserDefaults.standard.set(bottomTrigger.rawValue, forKey: Self.triggerBottomKey)
        UserDefaults.standard.set(dndEnabled, forKey: Self.dndEnabledKey)
        UserDefaults.standard.set(dndStartHour, forKey: Self.dndStartHKey)
        UserDefaults.standard.set(dndStartMin, forKey: Self.dndStartMKey)
        UserDefaults.standard.set(dndEndHour, forKey: Self.dndEndHKey)
        UserDefaults.standard.set(dndEndMin, forKey: Self.dndEndMKey)
        UserDefaults.standard.set(worldTimeHour, forKey: Self.worldTimeHKey)
        UserDefaults.standard.set(worldTimeMin, forKey: Self.worldTimeMKey)
        UserDefaults.standard.set(vibStrength, forKey: Self.vibStrengthKey)
    }

    private func loadSettings() {
        topTrigger = TriggerValue(rawValue: UserDefaults.standard.integer(forKey: Self.triggerTopKey)) ?? .none
        bottomTrigger = TriggerValue(rawValue: UserDefaults.standard.integer(forKey: Self.triggerBottomKey)) ?? .none
        dndEnabled = UserDefaults.standard.bool(forKey: Self.dndEnabledKey)
        dndStartHour = UserDefaults.standard.object(forKey: Self.dndStartHKey) as? Int ?? 22
        dndStartMin = UserDefaults.standard.integer(forKey: Self.dndStartMKey)
        dndEndHour = UserDefaults.standard.object(forKey: Self.dndEndHKey) as? Int ?? 7
        dndEndMin = UserDefaults.standard.integer(forKey: Self.dndEndMKey)
        worldTimeHour = UserDefaults.standard.integer(forKey: Self.worldTimeHKey)
        worldTimeMin = UserDefaults.standard.integer(forKey: Self.worldTimeMKey)
        vibStrength = UserDefaults.standard.integer(forKey: Self.vibStrengthKey)
    }
}
