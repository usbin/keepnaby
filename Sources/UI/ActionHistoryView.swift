import SwiftUI

struct ActionHistoryView: View {
    @EnvironmentObject var history: ActionHistoryManager
    @State private var showClearConfirm = false

    private var grouped: [(date: String, entries: [ActionHistoryEntry])] {
        let groups = Dictionary(grouping: history.entries) { $0.dateString }
        return groups.keys.sorted(by: >).map { key in
            (date: key, entries: groups[key] ?? [])
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if history.entries.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("실행 내역이 없습니다")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(grouped, id: \.date) { group in
                            Section(group.date) {
                                ForEach(group.entries) { entry in
                                    HStack(alignment: .top, spacing: 10) {
                                        Text(entry.timeString)
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .frame(width: 70, alignment: .leading)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(entry.trigger)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Text(entry.actionName)
                                                .font(.body)
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("실행 내역")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                trailing: Button("전체 삭제") { showClearConfirm = true }
                    .foregroundStyle(.red)
                    .disabled(history.entries.isEmpty)
            )
            .alert("전체 삭제", isPresented: $showClearConfirm) {
                Button("삭제", role: .destructive) { history.clear() }
                Button("취소", role: .cancel) {}
            } message: {
                Text("저장된 실행 내역이 모두 삭제됩니다.")
            }
        }
    }
}
