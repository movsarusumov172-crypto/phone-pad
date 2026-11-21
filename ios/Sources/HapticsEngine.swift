import CoreHaptics
import Foundation

/// Тактильная обратная связь на CoreHaptics: две полосы («низ» — вес, «верх» — текстура),
/// «щелчки» триггеров и отклик на нажатие кнопок.
final class HapticsEngine {
    private var engine: CHHapticEngine?
    private var supportsAudio = false
    private var isPreparing = false

    /// Последние значения полос — используются таймером, который играет непрерывные порции.
    private var bodyState: (low: Float, lowFreq: Float, high: Float, highFreq: Float) = (0, 0, 0, 0)
    /// Момент, до которого полосы ещё должны звучать (nil — держать до следующего сообщения).
    private var bodyDeadline: Date?
    private var bodyTimer: DispatchSourceTimer?
    private var intensityScale: Float

    /// Период «куска» непрерывной вибрации. Следующий кусок начинается сразу после
    /// предыдущего, поэтому звучание непрерывное и без щелчков на стыках.
    private let chunkDuration: TimeInterval = 0.03

    init(intensityScale: Float = 1.0) {
        self.intensityScale = max(0, min(1, intensityScale))
        prepare()
        startBodyTimer()
    }

    var isSupported: Bool { engine != nil }

    /// Общая интенсивность тактильной обратной связи (0…1).
    func setIntensityScale(_ value: Float) {
        intensityScale = max(0, min(1, value))
    }

    private func prepare() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        guard !isPreparing else { return }
        isPreparing = true
        defer { isPreparing = false }

        supportsAudio = CHHapticEngine.capabilitiesForHardware().supportsAudio

        do {
            let engine = try CHHapticEngine()
            engine.stoppedHandler = { [weak self] _ in self?.prepare() }
            engine.resetHandler = { [weak self] in self?.prepare() }
            try engine.start()
            self.engine = engine
        } catch {
            engine = nil
        }
    }

    // MARK: - Кнопки

    /// Короткий отклик при нажатии кнопки.
    func click(intensity: Float = 0.55, sharpness: Float = 0.85) {
        guard let engine else { return }
        let event = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity * intensityScale),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            ],
            relativeTime: 0)
        play(events: [event], duration: 0.06)
    }

    // MARK: - Триггеры

    /// Имитация «щелчка» адаптивного триггера: короткий резкий импульс.
    func trigger(left: Float, right: Float, duration: TimeInterval) {
        guard let engine else { return }
        var events: [CHHapticEvent] = []
        let length = max(0.02, min(0.25, duration))

        if left > 0.02 {
            events.append(CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: min(1, left) * intensityScale),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.95)
                ],
                relativeTime: 0))
        }

        if right > 0.02 {
            events.append(CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: min(1, right) * intensityScale),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.95)
                ],
                relativeTime: 0.02))
        }

        if !events.isEmpty {
            play(events: events, duration: length)
        }
    }

    // MARK: - Кузов (две полосы)

    /// Установить текущее состояние «кузовных» полос.
    /// `duration` — 0 означает «держать до следующего сообщения».
    func setBody(low: Float, lowFreq: Float, high: Float, highFreq: Float, duration: TimeInterval = 0) {
        bodyState = (low, lowFreq, high, highFreq)
        if duration > 0 {
            bodyDeadline = Date().addingTimeInterval(duration)
        } else if low <= 0.01 && high <= 0.01 {
            bodyDeadline = nil
        }
    }

    /// Немедленно прекратить «кузовную» вибрацию.
    func stopBody() {
        bodyState = (0, 0, 0, 0)
        bodyDeadline = nil
    }

    private func startBodyTimer() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInitiated))
        timer.schedule(deadline: .now(), repeating: .milliseconds(30))
        timer.setEventHandler { [weak self] in
            self?.playBodyChunk()
        }
        timer.resume()
        bodyTimer = timer
    }

    private func playBodyChunk() {
        // Эффект с истёкшим сроком действия выключаем сами — иначе телефон
        // будет вибрировать после окончания эффекта.
        if let deadline = bodyDeadline, Date() >= deadline {
            bodyState = (0, 0, 0, 0)
            bodyDeadline = nil
            return
        }

        let state = bodyState
        guard let engine, state.low > 0.01 || state.high > 0.01 else { return }

        var events: [CHHapticEvent] = []

        if state.low > 0.01 {
            events.append(CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: min(1, state.low) * intensityScale),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpnessFor(state.lowFreq)),
                    CHHapticEventParameter(parameterID: .hapticFrequency, value: frequencyFor(state.lowFreq))
                ],
                relativeTime: 0,
                duration: chunkDuration))
        }

        if state.high > 0.01 {
            events.append(CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: min(1, state.high) * intensityScale),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpnessFor(state.highFreq)),
                    CHHapticEventParameter(parameterID: .hapticFrequency, value: frequencyFor(state.highFreq))
                ],
                relativeTime: 0,
                duration: chunkDuration))
        }

        play(events: events, duration: chunkDuration)
    }

    /// Низкая частота → мягкая «гудящая» текстура, высокая → резкая.
    private func sharpnessFor(freq: Float) -> Float {
        let normalized = max(0, min(1, (freq - 20) / 200))
        return 0.15 + normalized * 0.8
    }

    private func frequencyFor(freq: Float) -> Float {
        max(10, min(300, freq))
    }

    private func play(events: [CHHapticEvent], duration: TimeInterval) {
        guard let engine, !events.isEmpty else { return }
        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            // тактильность недоступна — тихо продолжаем
        }
    }

    /// Поддерживает ли устройство аудио-тактильность (как у настоящего DualSense).
    var audioHapticsSupported: Bool { supportsAudio }
}
