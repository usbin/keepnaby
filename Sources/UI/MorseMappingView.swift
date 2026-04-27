import SwiftUI

// MARK: - 모스 명령 편집

struct MorseMappingEditView: View {
    let originalKey: String?  // nil이면 새로 만드는 중
    @EnvironmentObject var actionManager: ButtonActionManager
    @Environment(\.dismiss) var dismiss

    @State private var keyInput: String = ""
    @State private var action: ButtonAction = ButtonAction()
    @State private var label: String = ""

    private var normalizedKey: String {
        String(keyInput
            .uppercased()
            .filter { $0.isLetter || $0.isNumber }
            .prefix(ButtonActionManager.morseMaxCommandLength))
    }

    private var isValid: Bool {
        !normalizedKey.isEmpty && action.type != .none
    }

    private var isDuplicate: Bool {
        guard !normalizedKey.isEmpty else { return false }
        // 편집 중인 키 자신과의 일치는 중복 아님
        if let originalKey, originalKey == normalizedKey { return false }
        return actionManager.morseMappings[normalizedKey] != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("명령어") {
                    TextField("예: SOS, A1, M2", text: $keyInput)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                        .onChange(of: keyInput) { newValue in
                            let filtered = newValue.filter { $0.isLetter || $0.isNumber }
                            let upper = String(filtered.uppercased().prefix(ButtonActionManager.morseMaxCommandLength))
                            if upper != newValue { keyInput = upper }
                        }

                    Text("최대 \(ButtonActionManager.morseMaxCommandLength)자 (영문/숫자)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !normalizedKey.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("모스 부호")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(MorseDecoder.encodeString(normalizedKey))
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.orange)
                        }
                    }

                    if isDuplicate {
                        Text("이미 등록된 명령어입니다.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("설명 (선택)") {
                    TextField("예: Computer ON (상단)", text: $label)
                        .autocorrectionDisabled()
                }

                Section("동작") {
                    actionPicker(selection: $action)
                }
                ActionDetailView(action: $action)

                if originalKey != nil {
                    Section {
                        Button(role: .destructive) {
                            if let originalKey {
                                actionManager.morseMappings.removeValue(forKey: originalKey)
                                actionManager.saveMorse()
                            }
                            dismiss()
                        } label: {
                            HStack {
                                Spacer()
                                Label("이 명령 삭제", systemImage: "trash")
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle(originalKey == nil ? "모스 명령 추가" : "모스 명령 편집")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("취소") { dismiss() },
                trailing: Button("저장") {
                    saveMapping()
                }
                .disabled(!isValid || isDuplicate)
            )
            .onAppear {
                if let originalKey {
                    keyInput = originalKey
                    let existing = actionManager.morseMappings[originalKey] ?? ButtonAction()
                    action = existing
                    label = existing.label
                }
            }
        }
    }

    private func saveMapping() {
        guard isValid, !isDuplicate else { return }
        var saved = action
        saved.label = label
        if let originalKey, originalKey != normalizedKey {
            actionManager.morseMappings.removeValue(forKey: originalKey)
        }
        actionManager.morseMappings[normalizedKey] = saved
        actionManager.saveMorse()
        dismiss()
    }
}
