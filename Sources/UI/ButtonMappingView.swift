import SwiftUI

struct ButtonMappingView: View {
    @EnvironmentObject var actionManager: ButtonActionManager
    @State private var editingKey: ButtonKey?

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
                Section("상단 버튼") {
                    ForEach(ButtonActionManager.allButtons.filter { $0.button == 0 }, id: \.storageKey) { key in
                        buttonRow(key: key)
                    }
                }

                // Bottom button
                Section("하단 버튼") {
                    ForEach(ButtonActionManager.allButtons.filter { $0.button == 2 }, id: \.storageKey) { key in
                        buttonRow(key: key)
                    }
                }

                // Crown (fixed)
                Section("크라운") {
                    HStack {
                        Text("3초 홀드")
                        Spacer()
                        Text("폰 찾기 (고정)")
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
                Text(actionSummary(action))
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(.primary)
    }

    private func actionSummary(_ action: ButtonAction) -> String {
        switch action.type {
        case .none: return "없음"
        case .findPhone: return "폰 찾기"
        case .musicPlayPause: return "재생/일시정지"
        case .musicNext: return "다음 곡"
        case .musicPrevious: return "이전 곡"
        case .recordLocation: return "위치 기록"
        case .iftttWebhook: return "IFTTT: \(action.iftttEventName)"
        case .shortcut: return "단축어: \(action.shortcutName)"
        case .urlRequest: return "URL"
        }
    }
}

extension ButtonKey: Identifiable {
    var id: String { storageKey }
}

// MARK: - Action Edit

struct ActionEditView: View {
    let key: ButtonKey
    @EnvironmentObject var actionManager: ButtonActionManager
    @Environment(\.dismiss) var dismiss
    @State private var action: ButtonAction = ButtonAction()

    var body: some View {
        NavigationStack {
            Form {
                Section("\(key.displayButton) — \(key.displayEvent)") {
                    Picker("동작", selection: $action.type) {
                        Text("없음").tag(ButtonActionType.none)
                        Section("기본") {
                            Text("폰 찾기").tag(ButtonActionType.findPhone)
                        }
                        Section("음악") {
                            Text("재생/일시정지").tag(ButtonActionType.musicPlayPause)
                            Text("다음 곡").tag(ButtonActionType.musicNext)
                            Text("이전 곡").tag(ButtonActionType.musicPrevious)
                        }
                        Section("위치") {
                            Text("위치 기록").tag(ButtonActionType.recordLocation)
                        }
                        Section("고급") {
                            Text("IFTTT Webhook").tag(ButtonActionType.iftttWebhook)
                            Text("단축어 실행 (앱 열림)").tag(ButtonActionType.shortcut)
                            Text("URL 요청").tag(ButtonActionType.urlRequest)
                        }
                    }
                }

                switch action.type {
                case .iftttWebhook:
                    Section("IFTTT 이벤트") {
                        TextField("이벤트 이름", text: $action.iftttEventName)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                case .shortcut:
                    Section("단축어") {
                        TextField("단축어 이름 (정확히 입력)", text: $action.shortcutName)
                            .autocorrectionDisabled()
                    }
                case .urlRequest:
                    Section("URL") {
                        TextField("https://...", text: $action.urlString)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                    }
                default:
                    EmptyView()
                }
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
