import SwiftUI

struct NotificationMappingView: View {
    @EnvironmentObject var mappingManager: NotificationMappingManager
    @EnvironmentObject var ble: BLEManager
    @State private var applied = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("알림 카테고리별 진동 패턴과 바늘 위치를 설정합니다.\n시계가 iPhone ANCS 알림을 직접 감지합니다.\n앱이 꺼져 있어도 동작합니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("알림 필터") {
                    ForEach($mappingManager.filters) { $filter in
                        VStack(spacing: 8) {
                            HStack {
                                Image(systemName: filter.systemImage)
                                    .foregroundStyle(filter.enabled ? .blue : .gray)
                                    .frame(width: 24)

                                Text(filter.displayName)
                                    .bold(filter.isAllNotifications)

                                Spacer()

                                Toggle("", isOn: $filter.enabled)
                                    .labelsHidden()
                            }

                            if filter.enabled {
                                HStack(spacing: 16) {
                                    // 바늘 위치
                                    HStack(spacing: 4) {
                                        Image(systemName: "clock")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Picker("위치", selection: $filter.position) {
                                            ForEach(1...12, id: \.self) { num in
                                                Text("\(num)시").tag(num)
                                            }
                                        }
                                        .pickerStyle(.menu)
                                    }

                                    // 진동 패턴
                                    Picker("진동", selection: $filter.vibration) {
                                        ForEach(VibrationPattern.allCases) { pattern in
                                            Text(pattern.displayName).tag(pattern)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                }
                                .font(.caption)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                Section {
                    Button("시계에 적용") {
                        mappingManager.save()
                        mappingManager.applyToWatch(ble: ble)
                        applied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { applied = false }
                    }
                    .frame(maxWidth: .infinity)

                    if applied {
                        Text("적용 완료!")
                            .foregroundStyle(.green)
                            .frame(maxWidth: .infinity)
                    }
                }

                Section("참고") {
                    Text("• \"모든 알림\": 카테고리 무관 모든 알림에 반응\n• 바늘 위치: 알림 시 시침/분침이 가리킬 숫자\n• 진동: 알림 시 진동 횟수\n• 설정은 시계에 저장되므로 앱 없이도 동작")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("알림 매핑")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}