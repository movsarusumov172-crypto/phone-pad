import CoreMotion
import Foundation

/// Руление по наклону телефона (гироскоп) — то, чего нет у дешёвых падов.
final class MotionEngine {
    private let manager = CMMotionManager()
    private var centerRoll: Double = 0
    private var currentRoll: Double = 0
    private var rateX: Double = 0
    private var rateY: Double = 0

    private var smoothedRoll: Double = 0
    private var smoothedRateX: Double = 0
    private var smoothedRateY: Double = 0
    private var isSmoothed = false

    /// Максимальный угол наклона, соответствующий полному отклонению руля (градусы).
    var maxAngleDegrees: Double = 32
    /// Скорость отклика: 1 — мгновенно, меньше — плавнее.
    var smoothing: Double = 0.35

    var isRunning: Bool { manager.isDeviceMotionActive }

    func start() {
        guard manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            // roll — поворот вокруг продольной оси телефона; в ландшафте это и есть «руль».
            self.currentRoll = motion.attitude.roll
            self.rateX = motion.rotationRate.x
            self.rateY = motion.rotationRate.y
            self.applySmoothing()
        }
    }

    /// Фильтр низких частот: убирает дрожание рук, но не даёт «залипнуть» рулю.
    private func applySmoothing() {
        let alpha = max(0.05, min(1.0, 1.0 - smoothing))
        if !isSmoothed {
            smoothedRoll = currentRoll
            smoothedRateX = rateX
            smoothedRateY = rateY
            isSmoothed = true
            return
        }
        smoothedRoll += (currentRoll - smoothedRoll) * alpha
        smoothedRateX += (rateX - smoothedRateX) * alpha
        smoothedRateY += (rateY - smoothedRateY) * alpha
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        // При следующем запуске фильтр стартует заново от текущего положения.
        isSmoothed = false
    }

    /// Запомнить текущее положение как нейтральное.
    func calibrate() {
        centerRoll = isSmoothed ? smoothedRoll : currentRoll
    }

    var rollDegrees: Double {
        (isSmoothed ? smoothedRoll : currentRoll) * 180 / .pi
    }

    /// Угловая скорость в сотых градуса в секунду (для протокола).
    var gyroPitch: Int16 { Int16(max(-32000, min(32000, smoothedRateY * 100))) }
    var gyroRoll: Int16 { Int16(max(-32000, min(32000, smoothedRateX * 100))) }

    /// Текущее положение руля в диапазоне −1000…1000.
    var steering: Int16 {
        let roll = isSmoothed ? smoothedRoll : currentRoll
        let delta = roll - centerRoll
        let maxAngle = maxAngleDegrees * .pi / 180
        guard maxAngle > 0 else { return 0 }

        var normalized = delta / maxAngle
        normalized = max(-1, min(1, normalized))

        // небольшая мёртвая зона в центре и мягкая кривая
        if abs(normalized) < 0.06 {
            normalized = 0
        } else {
            let sign = normalized < 0 ? -1.0 : 1.0
            let magnitude = pow(abs(normalized), 1.25)
            normalized = sign * magnitude
        }

        return Int16(normalized * 1000)
    }
}
