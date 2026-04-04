import SwiftUI

struct NotificationMappingView: View {
    @EnvironmentObject var mappingManager: NotificationMappingManager
    @EnvironmentObject var ble: BLEManager
    @State private var applied = false
    @State private var showAddApp = false
    @State private var newAppBundleId = ""
    @State private var newAppName = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("알림이 오면 시계 바늘이 숫자를 가리키고 진동합니다.\n위치 = 진동 횟수 (1시=1회, 2시=2회, 3시=3회)\n설정은 시계에 저장되어 앱 없이도 동작합니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // MARK: - 카테고리 슬롯
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

                // MARK: - 앱 필터
                Section("앱별 필터") {
                    if mappingManager.appFilters.isEmpty {
                        Text("앱 필터 없음")
                            .foregroundStyle(.secondary)
                    }

                    ForEach($mappingManager.appFilters) { $filter in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(filter.name)
                                    .font(.body)
                                Text(filter.bundleId)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if filter.enabled {
                                Picker("", selection: $filter.vibration) {
                                    Text("1시").tag(1)
                                    Text("2시").tag(2)
                                    Text("3시").tag(3)
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 120)
                            }

                            Toggle("", isOn: $filter.enabled)
                                .labelsHidden()

                            Button {
                                mappingManager.removeAppFilter(id: filter.id)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    }

                    Button { showAddApp = true } label: {
                        Label("직접 추가", systemImage: "plus.circle")
                    }
                }

                // MARK: - 자주 쓰는 앱
                Section("자주 쓰는 앱 (탭하여 추가)") {
                    ForEach(NotificationMappingManager.commonApps, id: \.bundleId) { app in
                        let exists = mappingManager.appFilters.contains { $0.bundleId == app.bundleId }
                        Button {
                            if !exists {
                                mappingManager.addAppFilter(bundleId: app.bundleId, name: app.name)
                            }
                        } label: {
                            HStack {
                                Text(app.name)
                                Spacer()
                                if exists {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                } else {
                                    Text(app.bundleId)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                        .disabled(exists)
                    }
                }

                // MARK: - 적용
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
            .alert("앱 필터 추가", isPresented: $showAddApp) {
                TextField("Bundle ID", text: $newAppBundleId)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                TextField("앱 이름", text: $newAppName)
                Button("추가") {
                    if !newAppBundleId.isEmpty {
                        mappingManager.addAppFilter(
                            bundleId: newAppBundleId,
                            name: newAppName.isEmpty ? newAppBundleId : newAppName
                        )
                        newAppBundleId = ""
                        newAppName = ""
                    }
                }
                Button("취소", role: .cancel) {
                    newAppBundleId = ""
                    newAppName = ""
                }
            }
        }
    }
}
