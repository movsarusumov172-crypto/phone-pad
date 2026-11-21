import AVFoundation
import Foundation

/// Звуки «спикера» контроллера: клики, переключение передач, удары, ABS-пульс.
/// Все звуки синтезируются процедурно — asset-файлы не нужны.
final class SoundEngine {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let sampleRate: Double = 44100
    private var lastPlayed: [UInt8: Date] = [:]
    private var isEnabled = true

    init() {
        // Сессию настраиваем до старта движка: иначе звук может не подхватиться.
        // .ambient + mixWithOthers: не прерываем звук игры.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, options: [.mixWithOthers])
        try? session.setActive(true)

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.9
        try? engine.start()
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if !enabled {
            player.stop()
        }
    }

    /// Минимальный интервал между повторами одного звука (защита от «пулемёта»).
    private func shouldPlay(_ id: UInt8, minInterval: TimeInterval) -> Bool {
        let now = Date()
        if let last = lastPlayed[id], now.timeIntervalSince(last) < minInterval {
            return false
        }
        lastPlayed[id] = now
        return true
    }

    /// Минимальный интервал для каждого звука: телеметрия FH6 шлёт события
    /// десятки раз в секунду, и без ограничителя звук превращается в треск.
    private func minInterval(for soundId: UInt8) -> TimeInterval {
        switch soundId {
        case 1: return 0.03   // клик кнопки
        case 2: return 0.06   // переключение передачи
        case 3: return 0.50   // стартовый звук
        case 4: return 0.08   // удар
        case 5: return 0.10   // ABS-пульс
        case 6: return 0.25   // смена поверхности
        default: return 0.05
        }
    }

    func play(_ soundId: UInt8, parameter: UInt8 = 0) {
        guard isEnabled else { return }
        guard shouldPlay(soundId, minInterval: minInterval(for: soundId)) else { return }

        let buffer: AVAudioPCMBuffer?
        switch soundId {
        case 1: buffer = makeClick()
        case 2: buffer = makeGearShift()
        case 3: buffer = makeStartup()
        case 4: buffer = makeCollision(intensity: Float(parameter) / 255)
        case 5: buffer = makeAbsPulse()
        case 6: buffer = makeSurfaceChange()
        default: buffer = nil
        }

        guard let buffer else { return }
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        if !player.isPlaying {
            player.play()
        }
    }

    // MARK: - Синтез

    private func makeBuffer(duration: Double, fill: (Double) -> Float) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(duration * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!,
                                           frameCapacity: frames),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        for i in 0..<Int(frames) {
            let t = Double(i) / sampleRate
            channel[i] = max(-1, min(1, fill(t)))
        }
        return buffer
    }

    /// Короткий щелчок: шум + высокий тон с быстрым спадом.
    private func makeClick() -> AVAudioPCMBuffer? {
        makeBuffer(duration: 0.035) { (t: Double) -> Float in
            let decay = exp(-t * 180)
            let noise = Double.random(in: -1...1) * decay
            let tone = sin(2 * .pi * 2100 * t) * decay * 0.6
            return Float(noise * 0.5 + tone)
        }
    }

    /// Два коротких «тика» — имитация переключения передачи.
    private func makeGearShift() -> AVAudioPCMBuffer? {
        makeBuffer(duration: 0.16) { (t: Double) -> Float in
            let first = t < 0.05 ? exp(-t * 70) : 0
            let second = (t >= 0.06 && t < 0.12) ? exp(-(t - 0.06) * 70) : 0
            let noise = Double.random(in: -1...1) * 0.35
            let toneA = sin(2 * .pi * 1400 * t) * first
            let toneB = sin(2 * .pi * 900 * t) * second
            return Float((toneA + toneB) * 0.6 + noise * (first + second))
        }
    }

    /// Стартовый «аккорд» — как звук включения контроллера.
    private func makeStartup() -> AVAudioPCMBuffer? {
        makeBuffer(duration: 0.55) { (t: Double) -> Float in
            let tones: [(Double, Double)] = [(523.25, 0.0), (659.25, 0.12), (783.99, 0.24)]
            var value = 0.0
            for (freq, start) in tones where t >= start {
                let local = t - start
                let env = exp(-local * 9) * min(1, local * 40)
                value += sin(2 * .pi * freq * local) * env * 0.28
            }
            return Float(value)
        }
    }

    /// Удар: низкий спад + шум.
    private func makeCollision(intensity: Float) -> AVAudioPCMBuffer? {
        let amp = max(0.15, min(1, intensity))
        return makeBuffer(duration: 0.35) { (t: Double) -> Float in
            let freq = 130 - 90 * min(1, t / 0.3)
            let env = exp(-t * 14)
            let body = sin(2 * .pi * freq * t) * env * 0.9
            let noise = Double.random(in: -1...1) * exp(-t * 40) * 0.5
            return Float((body + noise) * Double(amp))
        }
    }

    /// Тик ABS — очень короткий и сухой.
    private func makeAbsPulse() -> AVAudioPCMBuffer? {
        makeBuffer(duration: 0.03) { (t: Double) -> Float in
            let decay = exp(-t * 300)
            return Float(sin(2 * .pi * 3200 * t) * decay * 0.45)
        }
    }

    /// Смена поверхности: нарастающий шум.
    private func makeSurfaceChange() -> AVAudioPCMBuffer? {
        makeBuffer(duration: 0.3) { (t: Double) -> Float in
            let env = min(1, t / 0.15) * exp(-max(0, t - 0.15) * 8)
            return Float(Double.random(in: -1...1) * env * 0.35)
        }
    }
}
