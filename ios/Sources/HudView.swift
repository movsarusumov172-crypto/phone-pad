import SwiftUI

/// Компактный HUD для строки статуса: скорость, передача, обороты, газ/тормоз.
/// Живёт прямо в верхней полосе — отдельно он перекрывал бы зону руля.
struct HudView: View {
    let hud: HudData

    var body: some View {
        HStack(spacing: 8) {
            Text("\(hud.speed)")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)

            Text("км/ч")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))

            if hud.isRaceOn {
                Text(hud.gear == 0 ? "N" : "\(hud.gear)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(hud.gear > 0 ? .orange : .white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))

                bar(value: Double(hud.rpm) / Double(max(1, hud.maxRpm)), color: .orange, width: 64, height: 5)

                HStack(spacing: 4) {
                    bar(value: Double(hud.throttle) / 255, color: .green, width: 22, height: 4)
                    bar(value: Double(hud.brake) / 255, color: .red, width: 22, height: 4)
                }
            }
        }
        .foregroundStyle(.white)
    }

    private func bar(value: Double, color: Color, width: CGFloat, height: CGFloat) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18))
                Capsule()
                    .fill(color)
                    .frame(width: geo.size.width * max(0, min(1, value)))
            }
        }
        .frame(width: width, height: height)
    }
}

/// Верхняя панель: статус связи, HUD, «световая полоса» и кнопки.
struct StatusBar: View {
    let status: ConnectionStatus
    let gyroEnabled: Bool
    let message: String
    let lightBar: LightBarColor
    let hud: HudData
    let showHUD: Bool
    let onSettings: () -> Void
    let onGyro: () -> Void
    let onCalibrate: () -> Void
    let onConnect: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 10) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)

                Text(status.rawValue)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))

                if showHUD {
                    HudView(hud: hud)
                }

                if !message.isEmpty {
                    Text(message)
                        .font(.system(size: 10, weight: .medium))
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
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 9)
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
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
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
