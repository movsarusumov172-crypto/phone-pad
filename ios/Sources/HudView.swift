import SwiftUI

/// Индикатор скорости/передачи поверх экрана пада.
struct HudView: View {
    let hud: HudData

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text("\(hud.speed)")
                    .font(.system(size: 46, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                Text("км/ч")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))

                if hud.isRaceOn {
                    Text(hud.gear == 0 ? "N" : "\(hud.gear)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(hud.gear > 0 ? .orange : .white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                }
            }

            if hud.isRaceOn {
                VStack(alignment: .leading, spacing: 3) {
                    bar(value: Double(hud.rpm) / Double(max(1, hud.maxRpm)), color: .orange, height: 6)
                    HStack(spacing: 10) {
                        bar(value: Double(hud.throttle) / 255, color: .green, height: 4)
                        bar(value: Double(hud.brake) / 255, color: .red, height: 4)
                    }
                    if hud.slip > 0.05 {
                        Text("slip \(String(format: "%.2f", hud.slip))")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.yellow)
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .padding(12)
        .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
        .shadow(radius: 6)
    }

    private func bar(value: Double, color: Color, height: CGFloat) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.15))
                Capsule()
                    .fill(color)
                    .frame(width: geo.size.width * max(0, min(1, value)))
            }
        }
        .frame(height: height)
    }
}

/// Верхняя панель: статус связи, «световая полоса» и кнопки.
struct StatusBar: View {
    let status: ConnectionStatus
    let gyroEnabled: Bool
    let message: String
    let lightBar: LightBarColor
    let onSettings: () -> Void
    let onGyro: () -> Void
    let onCalibrate: () -> Void
    let onConnect: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 12) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 9, height: 9)

                Text(status.rawValue)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))

                if !message.isEmpty {
                    Text(message)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 4)

                if gyroEnabled {
                    Button(action: onCalibrate) {
                        Image(systemName: "scope")
                            .font(.system(size: 13, weight: .semibold))
                            .padding(8)
                            .background(Color.white.opacity(0.15), in: Capsule())
                            .foregroundStyle(.white)
                    }
                    .accessibilityLabel("Отцентрировать руль по гироскопу")
                }

                Button(action: onGyro) {
                    Label("Гиро", systemImage: "gyroscope")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(gyroEnabled ? Color.orange.opacity(0.85) : Color.white.opacity(0.15),
                                    in: Capsule())
                        .foregroundStyle(.white)
                }

                Button(action: onConnect) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(8)
                        .background(Color.white.opacity(0.15), in: Capsule())
                        .foregroundStyle(.white)
                }
                .accessibilityLabel(status == .connected ? "Отключиться" : "Подключиться")

                Button(action: onSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(8)
                        .background(Color.white.opacity(0.15), in: Capsule())
                        .foregroundStyle(.white)
                }
                .accessibilityLabel("Настройки")
            }

            // Эмуляция «световой полосы» контроллера: iOS не умеет менять цвет LED,
            // поэтому показываем цветную полосу под строкой статуса.
            Rectangle()
                .fill(Color(red: Double(lightBar.r), green: Double(lightBar.g), blue: Double(lightBar.b)))
                .frame(height: 2)
                .opacity(lightBar.isOff ? 0 : 1)
                .animation(.easeOut(duration: 0.15), value: lightBar)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.35), in: Capsule())
    }

    private var statusColor: Color {
        switch status {
        case .connected: return .green
        case .connecting: return .yellow
        case .failed: return .red
        case .disconnected: return .orange
        }
    }
}
