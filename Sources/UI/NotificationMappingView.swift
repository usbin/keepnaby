import SwiftUI

struct NotificationMappingView: View {
    @EnvironmentObject var mappingManager: NotificationMappingManager
    @EnvironmentObject var ble: BLEManager
    @State private var applied = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("알림 카테고리별 진동 패턴을 설정합니다.\n시계가 iPhone ANCS 알림을 직접 감지하여 진동합니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("알림 필터") {
                    ForEach($mappingManager.filters) { $filter in
                        HStack {
                            Image(systemName: filter.category.systemImage)
                                .foregroundStyle(filter.enabled ? .blue : .gray)
                                .frame(width: 24)

                            Text(filter.category.displayName)

                            Spacer()

                            if filter.enabled {
                                Picker("", selection: $filter.vibration) {
                                    ForEach(VibrationPattern.allCases) { pattern in
                                        Text(pattern.displayName).tag(pattern)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 100)
                            }

                            Toggle("", isOn: $filter.enabled)
                                .labelsHidden()
                        }
                    }
                }

                Section("현재 설정") {
                    let active = mappingManager.filters.filter { $0.enabled }
                    if active.isEmpty {
                        Text("활성화된 필터 없음")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(active) { filter in
                            HStack {
                                Image(systemName: filter.category.systemImage)
                                    .foregroundStyle(.blue)
                                    .frame(width: 24)
                                Text(filter.category.displayName)
                                Spacer()
                                Text(filter.vibration.displayName)
                                    .foregroundStyle(.secondary)
                            }
                        }
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
            }
            .navigationTitle("알림 매핑")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}