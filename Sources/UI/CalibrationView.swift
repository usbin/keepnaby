import SwiftUI

struct CalibrationView: View {
    @EnvironmentObject var ble: BLEManager
    @Binding var isPresented: Bool
    @State private var isCalibrating = false

    // Nord: motor 0 = hour, motor 1 = minute
    var body: some View {
        VStack(spacing: 24) {
            Text("바늘 영점 조정")
                .font(.title2)
                .bold()

            Text("시계를 보면서 시침과 분침을\n정확히 12시 방향으로 맞춰주세요.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            if !isCalibrating {
                Button("캘리브레이션 시작") {
                    ble.sendCommand(name: "recalibrate", value: true)
                    isCalibrating = true
                    ble.log("캘리브레이션 모드 진입")
                }
                .buttonStyle(.borderedProminent)
            } else {
                VStack(spacing: 20) {
                    // Hour hand
                    HStack {
                        Text("시침")
                            .frame(width: 40)
                            .bold()
                        Button { move(motor: 0, steps: -10) } label: {
                            Image(systemName: "backward.fill")
                        }
                        Button { move(motor: 0, steps: -1) } label: {
                            Image(systemName: "chevron.left")
                        }
                        Spacer()
                        Button { move(motor: 0, steps: 1) } label: {
                            Image(systemName: "chevron.right")
                        }
                        Button { move(motor: 0, steps: 10) } label: {
                            Image(systemName: "forward.fill")
                        }
                    }
                    .font(.title3)

                    // Minute hand
                    HStack {
                        Text("분침")
                            .frame(width: 40)
                            .bold()
                        Button { move(motor: 1, steps: -10) } label: {
                            Image(systemName: "backward.fill")
                        }
                        Button { move(motor: 1, steps: -1) } label: {
                            Image(systemName: "chevron.left")
                        }
                        Spacer()
                        Button { move(motor: 1, steps: 1) } label: {
                            Image(systemName: "chevron.right")
                        }
                        Button { move(motor: 1, steps: 10) } label: {
                            Image(systemName: "forward.fill")
                        }
                    }
                    .font(.title3)

                    Text("◀ 반시계  /  시계 ▶")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)

                Button("완료 — 12시에 맞춤") {
                    ble.sendCommand(name: "recalibrate", value: false)
                    isCalibrating = false
                    isPresented = false
                    ble.log("캘리브레이션 완료")
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }

            if !isCalibrating {
                Button("건너뛰기") {
                    isPresented = false
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private func move(motor: Int, steps: Int) {
        ble.sendCommand(name: "recalibrate_move", value: [motor, steps])
    }
}
