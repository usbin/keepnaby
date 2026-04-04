import SwiftUI

struct NotificationMappingView: View {
    @EnvironmentObject var mappingManager: NotificationMappingManager
    @EnvironmentObject var ble: BLEManager
    @State private var applied = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("알림이 오면 시계 바늘이 숫자를 가리키고 진동합니다.\n위치 = 진동 횟수 (1시=1회, 2시=2회, 3시=3회)\n설정은 시계에 저장되어 앱 없이도 동작합니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach($mappingManager.slots) { $slot in
                    Section {
                        HStack {
                            Text(slot.positionName)
                                .font(.headline)
                            Spacer()
                            Toggle("", isOn: $slot.enabled)
                                .labelsHidden()
                        }

                        if slot.enabled {
                            ForEach(AncsCategory.allCases) { cat in
                                HStack {
                                    Image(systemName: cat.systemImage)
                                        .foregroundStyle(slot.hasCategory(cat) ? .blue : .gray)
                                        .frame(width: 24)
                                    Text(cat.displayName)
                                    Spacer()
                                    if slot.hasCategory(cat) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.blue)
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    slot.toggleCategory(cat)
                                    mappingManager.save()
                                }
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
