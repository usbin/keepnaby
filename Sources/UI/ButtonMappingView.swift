import SwiftUI

struct ButtonMappingView: View {
    @EnvironmentObject var actionManager: ButtonActionManager
    @State private var editingKey: ButtonKey?
    @State private var addingMorse = false
    @State private var editingMorseKey: String?

    var body: some View {
        NavigationStack {
            List {
                // IFTTT Key
                Section("IFTTT 설정") {
                    HStack {
                        Text("Webhook Key")
                            .foregroundStyle(.secondary)
                        TextField("IFTTT Key 입력", text: $actionManager.iftttKey)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                }

                // Top button
                Section {
                    ForEach(ButtonActionManager.allButtons.filter { $0.button == 0 }, id: \.storageKey) { key in
                        buttonRow(key: key)
                    }
                } header: {
                    Text("상단 버튼")
                } footer: {
                    Text("모스모드 중 길게 누름 → 점진적 취소 (등록된 일반 동작은 무시됨)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Bottom button
                Section {
                    ForEach(ButtonActionManager.allButtons.filter { $0.button == 2 }, id: \.storageKey) { key in
                        buttonRow(key: key)
                    }
                    HStack {
                        Text("길게 누름")
                        Spacer()
                        Text("모스 입력모드 (고정)")
                            .foregroundStyle(.orange)
                            .font(.caption)
                    }
                } header: {
                    Text("하단 버튼")
                }

                Section {
                    Text("위치 기록 사용 시: 설정 → 개인정보 보호 및 보안 → 위치 서비스 → Keepnaby → '항상'으로 변경해주세요.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // 모스부호 명령 매핑
                Section {
                    Text("""
                    하단 길게 → 모스모드 시작
                    하단 1회=·(점)  하단 2회=−(대시)
                    상단 1회 → 한 문자 확정
                    상단 길게 → 점진적 취소 (1차: 현재 문자, 2차: 전체)
                    하단 길게(다시) → 명령 실행 / 종료
                    """)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    ForEach(actionManager.morseMappings.keys.sorted(), id: \.self) { key in
                        morseRow(key: key)
                    }

                    Button {
                        addingMorse = true
                    } label: {
                        Label("명령 추가", systemImage: "plus.circle")
                    }
                } header: {
                    Text("모스부호 명령 매핑")
                } footer: {
                    if actionManager.morseMappings.isEmpty {
                        Text("등록된 명령이 없습니다. 추가해 주세요.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("버튼 매핑")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $editingKey) { key in
                ActionEditView(key: key)
                    .environmentObject(actionManager)
            }
            .sheet(isPresented: $addingMorse) {
                MorseMappingEditView(originalKey: nil)
                    .environmentObject(actionManager)
            }
            .sheet(item: $editingMorseKey) { key in
                MorseMappingEditView(originalKey: key)
                    .environmentObject(actionManager)
            }
        }
    }

    private func buttonRow(key: ButtonKey) -> some View {
        let action = actionManager.getAction(for: key)
        return Button {
            editingKey = key
        } label: {
            HStack {
                Text(key.displayEvent)
                Spacer()
                Text(action.summary)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(.primary)
    }

    private func morseRow(key: String) -> some View {
        let action = actionManager.morseMappings[key] ?? ButtonAction()
        return Button {
            editingMorseKey = key
        } label: {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(key)
                        .font(.system(.body, design: .monospaced))
                    Text(MorseDecoder.encodeString(key))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.orange)
                }
                Spacer()
                Text(action.summary)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(.primary)
    }
}

extension ButtonKey: Identifiable {
    var id: String { storageKey }
}

extension String: @retroactive Identifiable {
    public var id: String { self }
}

// MARK: - Action Edit (일반 버튼)

struct ActionEditView: View {
    let key: ButtonKey
    @EnvironmentObject var actionManager: ButtonActionManager
    @Environment(\.dismiss) var dismiss
    @State private var action: ButtonAction = ButtonAction()

    var body: some View {
        NavigationStack {
            Form {
                Section("\(key.displayButton) — \(key.displayEvent)") {
                    actionPicker(selection: $action)
                }
                actionDetail(action: $action)
            }
            .navigationTitle("동작 설정")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("취소") { dismiss() },
                trailing: Button("저장") {
                    actionManager.setAction(for: key, action: action)
                    dismiss()
                }
            )
            .onAppear {
                action = actionManager.getAction(for: key)
            }
        }
    }
}

// MARK: - Shared Picker & Detail

@ViewBuilder
func actionPicker(selection: Binding<ButtonAction>) -> some View {
    Picker("동작", selection: selection.type) {
        Text("없음").tag(ButtonActionType.none)
        Section("기본") {
            Text("폰 찾기").tag(ButtonActionType.findPhone)
            Text("오늘 날짜 확인").tag(ButtonActionType.showDate)
            Text("배터리 잔량 표시").tag(ButtonActionType.showBattery)
            Text("걸음수 확인").tag(ButtonActionType.showSteps)
        }
        Section("음악") {
            Text("재생/일시정지").tag(ButtonActionType.musicPlayPause)
            Text("다음 곡").tag(ButtonActionType.musicNext)
            Text("이전 곡").tag(ButtonActionType.musicPrevious)
        }
        Section("재미") {
            Text("위치 기록").tag(ButtonActionType.recordLocation)
            Text("랜덤 주사위").tag(ButtonActionType.randomDice)
        }
        Section("고급") {
            Text("IFTTT Webhook").tag(ButtonActionType.iftttWebhook)
            Text("단축어 실행 (앱 열림)").tag(ButtonActionType.shortcut)
            Text("URL 요청").tag(ButtonActionType.urlRequest)
        }
    }
}

@ViewBuilder
func actionDetail(action: Binding<ButtonAction>) -> some View {
    switch action.wrappedValue.type {
    case .findPhone:
        Section("폰 찾기 옵션") {
            Toggle("시스템 볼륨 최대화 (작동 후 복원 안 됨)", isOn: Binding(
                get: { FindMyPhone.maxVolumeEnabled },
                set: { FindMyPhone.maxVolumeEnabled = $0 }
            ))
        }
    case .iftttWebhook:
        Section("IFTTT 이벤트") {
            TextField("이벤트 이름", text: action.iftttEventName)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
    case .shortcut:
        Section("단축어") {
            TextField("단축어 이름 (정확히 입력)", text: action.shortcutName)
                .autocorrectionDisabled()
        }
    case .urlRequest:
        Section("URL") {
            TextField("https://...", text: action.urlString)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
        }
    case .randomDice:
        Section("주사위 범위") {
            Stepper("1시 ~ \(action.wrappedValue.diceMax)시",
                    value: action.diceMax, in: 2...12)
            Text("버튼 누르면 12시부터 회전하며 1~\(action.wrappedValue.diceMax) 중 무작위 시각 위치에서 멈추고 진동합니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    default:
        EmptyView()
    }
}
