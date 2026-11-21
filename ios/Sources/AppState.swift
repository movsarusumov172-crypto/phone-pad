import Combine
import Foundation
import SwiftUI
import UIKit

/// Данные HUD, приходящие с ПК из телеметрии FH6.
struct HudData {
    var speed = 0
    var gear = 0
    var rpm = 0
    var maxRpm = 7500
    var lateralG: Float = 0
    var throttle = 0
    var brake = 0
    var slip: Float = 0
    var isRaceOn = false
    var onRumbleStrip = false
}

/// Цвет «световой полосы» (эмуляция light bar контроллера).
/// Хранится как числа, а не как `Color`, чтобы его можно было сравнивать.
struct LightBarColor: Equatable {
    var r: Double = 0
    var g: Double = 0
    var b: Double = 0

    static let off = LightBarColor()

    var isOff: Bool { r == 0 && g == 0 && b == 0 }
}

/// Общее состояние приложения: связь, ввод, тактильность, звук, HUD.
final class AppState: ObservableObject {
    @Published var serverHost: String = ""
    @Published var serverPort: Int = 8888
    @Published var feedbackPort: Int = 8889
    @Published var layout: PadLayoutKind = .full
    @Published var gyroEnabled = false
    @Published var showHUD = true
    @Published var hapticsEnabled = true
    @Published var soundEnabled = true
    @Published var intensity: Double = 1.0
    @Published var hud = HudData()
    @Published var status: ConnectionStatus = .disconnected
    @Published var showSettings = false

    /// Текст последнего сообщения от сервера (показывается в верхней панели).
    @Published var serverMessage: String = ""

    /// Цвет «световой полосы» (эмуляция light bar контроллера).
    @Published var lightBar = LightBarColor.off

    let pad = PadController()
    let net = NetClient()

    private let haptics = HapticsEngine()
    private let sounds = SoundEngine()
    private let motion = MotionEngine()
    private var sendTimer: DispatchSourceTimer?
    private var cancellables = Set<AnyCancellable>()

    init() {
        // Настройки подключения запоминаются между запусками — не надо вводить
        // IP каждый раз заново.
        let defaults = UserDefaults.standard
        serverHost = defaults.string(forKey: "serverHost") ?? ""
        serverPort = defaults.object(forKey: "serverPort") as? Int ?? 8888
        feedbackPort = defaults.object(forKey: "feedbackPort") as? Int ?? 8889

        net.onFeedback = { [weak self] message in
            self?.handle(message)
        }
        net.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                guard let self else { return }
                self.status = value
                if value == .connected {
                    self.serverMessage = ""
                }
            }
            .store(in: &cancellables)

        net.$lastError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                guard let self, !value.isEmpty else { return }
                self.serverMessage = value
            }
            .store(in: &cancellables)

        pad.onButtonPress = { [weak self] in
            guard let self, self.hapticsEnabled else { return }
            self.haptics.click(intensity: Float(self.intensity) * 0.6)
        }

        $layout
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in self?.pad.layoutKind = value }
            .store(in: &cancellables)

        $soundEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in self?.sounds.setEnabled(value) }
            .store(in: &cancellables)

        $hapticsEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                guard let self else { return }
                if !value {
                    // Выключаем тактильность по-настоящему: глушим текущие полосы,
                    // иначе вибрация продолжается до следующего пакета от сервера.
                    self.haptics.setBody(low: 0, lowFreq: 0, high: 0, highFreq: 0)
                }
            }
            .store(in: &cancellables)

        startSendLoop()
    }

    deinit {
        sendTimer?.cancel()
    }

    // MARK: - Связь

    func connect() {
        let host = serverHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else {
            serverMessage = "Укажите IP-адрес ПК"
            return
        }

        let defaults = UserDefaults.standard
        defaults.set(host, forKey: "serverHost")
        defaults.set(serverPort, forKey: "serverPort")
        defaults.set(feedbackPort, forKey: "feedbackPort")

        net.start(host: host,
                  port: UInt16(clamping: serverPort),
                  feedbackPort: UInt16(clamping: feedbackPort))
    }

    func disconnect() {
        net.sendGoodbye()
        net.stop()
        // Сбрасываем пад: иначе в игре останутся зажатые педаль и кнопки.
        pad.reset()
        haptics.setBody(low: 0, lowFreq: 0, high: 0, highFreq: 0)
    }

    /// Полный сброс ввода (сворачивание приложения, потеря связи).
    func resetPad() {
        pad.reset()
        haptics.stopBody()
    }

    func toggleGyro() {
        gyroEnabled.toggle()
        if gyroEnabled {
            motion.start()
            // Центр захватывается после того, как телефон успел замереть в руках.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.motion.calibrate()
            }
        } else {
            motion.stop()
        }
    }

    func calibrateGyro() {
        motion.calibrate()
    }

    func setIntensity(_ value: Double) {
        intensity = value
        haptics.setIntensityScale(Float(value))
    }

    // MARK: - Цикл отправки

    private func startSendLoop() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInitiated))
        timer.schedule(deadline: .now(), repeating: .milliseconds(10))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            var state = self.pad.currentState
            if self.gyroEnabled {
                state.leftX = self.motion.steering
                state.gyroPitch = self.motion.gyroPitch
                state.gyroRoll = self.motion.gyroRoll
            }
            self.net.sendState(state, gyroActive: self.gyroEnabled)
        }
        timer.resume()
        sendTimer = timer
    }

    // MARK: - Обратная связь

    private func handle(_ message: FeedbackMessage) {
        switch message.kind {
        case .body:
            if hapticsEnabled, let body = message.body {
                haptics.setBody(low: body.low, lowFreq: body.lowFreq,
                                high: body.high, highFreq: body.highFreq,
                                duration: body.duration)
            }

        case .trigger:
            if hapticsEnabled, let trigger = message.trigger {
                haptics.trigger(left: trigger.left, right: trigger.right, duration: trigger.duration)
            }

        case .rumble:
            if hapticsEnabled, let rumble = message.rumble {
                // «Большой» мотор — низкая частота, «малый» — высокая.
                haptics.setBody(low: rumble.large, lowFreq: 45,
                                high: rumble.small, highFreq: 130)
            }

        case .sound:
            if let id = message.soundId {
                let param = message.payload.count > 1 ? message.payload[1] : 0
                sounds.play(id, parameter: param)
            }

        case .hud:
            if let h = message.hud {
                hud = HudData(speed: h.speed,
                              gear: h.gear,
                              rpm: h.rpm,
                              maxRpm: h.maxRpm > 0 ? h.maxRpm : 7500,
                              lateralG: h.lateralG,
                              throttle: h.throttle,
                              brake: h.brake,
                              slip: h.slip,
                              isRaceOn: (h.flags & 1) != 0,
                              onRumbleStrip: (h.flags & 2) != 0)
            }

        case .led:
            if let led = message.led {
                let color = LightBarColor(r: led.r, green: led.g, blue: led.b)
                lightBar = color
                // Гасим подсветку через короткое время, чтобы не горела постоянно.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                    guard let self, self.lightBar == color else { return }
                    self.lightBar = .off
                }
            }

        case .status:
            if let s = message.status {
                serverMessage = ServerMessages.text(for: s.code)
            }

        default:
            break
        }
    }
}

/// Расшифровка кодов статуса, которые присылает PC-сервер.
enum ServerMessages {
    static func text(for code: UInt8) -> String {
        switch code {
        case 1: return "Телефон подключён"
        case 2: return "Телефон отключён"
        case 3: return "Сервер готов"
        default: return ""
        }
    }
}
