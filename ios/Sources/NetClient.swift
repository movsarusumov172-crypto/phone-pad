import Foundation
import Network

enum ConnectionStatus: String {
    case disconnected = "нет связи"
    case connecting = "подключение…"
    case connected = "подключено"
    case failed = "ошибка"
}

/// Сообщение обратной связи от ПК к телефону.
struct FeedbackMessage {
    enum Kind: UInt8 {
        case rumble = 1
        case body = 2
        case trigger = 3
        case sound = 4
        case hud = 5
        case led = 6
        case status = 7
    }

    let kind: Kind
    let payload: Data

    var body: (low: Float, lowFreq: Float, high: Float, highFreq: Float, duration: TimeInterval)? {
        guard kind == .body, payload.count >= 6 else { return nil }
        let low = Float(payload[0]) / 255
        let lowFreq = Float(payload[1])
        let high = Float(payload[2]) / 255
        let highFreq = Float(payload[3])
        let duration = Double(UInt16(payload[4]) | (UInt16(payload[5]) << 8)) / 1000
        return (low, lowFreq, high, highFreq, duration)
    }

    var trigger: (left: Float, right: Float, duration: TimeInterval)? {
        guard kind == .trigger, payload.count >= 4 else { return nil }
        let left = Float(payload[0]) / 255
        let right = Float(payload[1]) / 255
        let duration = Double(UInt16(payload[2]) | (UInt16(payload[3]) << 8)) / 1000
        return (left, right, duration)
    }

    var rumble: (large: Float, small: Float)? {
        guard kind == .rumble, payload.count >= 2 else { return nil }
        return (Float(payload[0]) / 255, Float(payload[1]) / 255)
    }

    var soundId: UInt8? {
        guard kind == .sound, !payload.isEmpty else { return nil }
        return payload[0]
    }

    /// HUD. С 13 байт приходит максимальное число оборотов (макс. красная зона).
    var hud: (speed: Int, gear: Int, rpm: Int, maxRpm: Int, lateralG: Float, throttle: Int, brake: Int, slip: Float, flags: UInt8)? {
        guard kind == .hud, payload.count >= 11 else { return nil }
        let speed = Int(payload[0]) | (Int(payload[1]) << 8)
        let gear = Int(payload[2])
        let rpm = Int(payload[3]) | (Int(payload[4]) << 8)
        let g = Int(Int16(bitPattern: UInt16(payload[5]) | (UInt16(payload[6]) << 8)))
        let throttle = Int(payload[7])
        let brake = Int(payload[8])
        let slip = Float(payload[9]) / 40
        let flags = payload[10]
        let maxRpm = payload.count >= 13 ? Int(payload[11]) | (Int(payload[12]) << 8) : 7500
        return (speed, gear, rpm, maxRpm, Float(g) / 100, throttle, brake, slip, flags)
    }

    var led: (r: Float, g: Float, b: Float)? {
        guard kind == .led, payload.count >= 3 else { return nil }
        return (Float(payload[0]) / 255, Float(payload[1]) / 255, Float(payload[2]) / 255)
    }

    var status: (code: UInt8, detail: UInt8)? {
        guard kind == .status, payload.count >= 1 else { return nil }
        return (payload[0], payload.count >= 2 ? payload[1] : 0)
    }
}

/// Сетевой клиент: шлёт состояние пада на ПК и принимает обратную связь.
final class NetClient: ObservableObject {
    @Published var status: ConnectionStatus = .disconnected
    @Published var lastError: String = ""

    var onFeedback: ((FeedbackMessage) -> Void)?

    private var connection: NWConnection?
    private var listener: NWListener?
    private var peers: [ObjectIdentifier: NWConnection] = [:]
    private let queue = DispatchQueue(label: "com.phonepad.network")
    private var sequence: UInt16 = 0
    private var serverHost: String = ""
    private var serverPort: UInt16 = 8888
    private var feedbackPort: UInt16 = 8889
    private var keepAliveTimer: DispatchSourceTimer?
    private var lastAnswerUtc = Date.distantPast

    /// Как часто шлём пакет-пинг, чтобы контролировать живость канала.
    private let pingInterval: TimeInterval = 2.0

    /// Через сколько секунд без ответа от ПК считаем связь потерянной.
    private let answerTimeout: TimeInterval = 6.0

    func start(host: String, port: UInt16, feedbackPort: UInt16 = 8889) {
        stop()
        serverHost = host
        serverPort = port
        self.feedbackPort = feedbackPort
        status = .connecting
        lastError = ""

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            status = .failed
            lastError = "Некорректный порт: \(port)"
            return
        }

        let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .udp)
        connection = conn
        conn.stateUpdateHandler = { [weak self] newState in
            DispatchQueue.main.async {
                guard let self else { return }
                switch newState {
                case .ready:
                    self.status = .connected
                    self.lastAnswerUtc = Date()
                    self.sendHello()
                case .failed(let error):
                    self.status = .failed
                    self.lastError = error.localizedDescription
                case .waiting(let error):
                    self.status = .connecting
                    self.lastError = error.localizedDescription
                case .cancelled:
                    if self.status != .disconnected {
                        self.status = .disconnected
                    }
                default:
                    break
                }
            }
        }
        conn.start(queue: queue)

        startFeedbackListener()
        startKeepAlive()
    }

    func stop() {
        keepAliveTimer?.cancel()
        keepAliveTimer = nil
        if let connection {
            connection.cancel()
            connection = nil
        }
        if let listener {
            listener.cancel()
            listener = nil
        }
        peers.removeAll()
        sequence = 0
        status = .disconnected
    }

    // MARK: - Отправка

    func sendState(_ state: PadState, gyroActive: Bool) {
        guard let connection else { return }
        sequence = sequence &+ 1
        let data = WireFormat.encode(state: state, sequence: sequence, gyroActive: gyroActive)
        connection.send(content: data, contentContext: .defaultMessage, isComplete: true, completion: .contentProcessed { error in
            if let error {
                DispatchQueue.main.async { self.lastError = error.localizedDescription }
            }
        })
    }

    private func sendHello() {
        connection?.send(content: WireFormat.encodeControl(.hello),
                         contentContext: .defaultMessage,
                         isComplete: true,
                         completion: .contentProcessed { _ in })
    }

    func sendGoodbye() {
        connection?.send(content: WireFormat.encodeControl(.goodbye),
                         contentContext: .defaultMessage,
                         isComplete: true,
                         completion: .contentProcessed { _ in })
    }

    /// Пинг-пакет: сервер отвечает статусом, поэтому его ответ — признак живой связи.
    private func sendPing() {
        connection?.send(content: WireFormat.encodeControl(.ping),
                         contentContext: .defaultMessage,
                         isComplete: true,
                         completion: .contentProcessed { _ in })
    }

    private func startKeepAlive() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + pingInterval, repeating: pingInterval)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.sendPing()

            let silence = Date().timeIntervalSince(self.lastAnswerUtc)
            if silence > self.answerTimeout {
                DispatchQueue.main.async {
                    guard self.status == .connected else { return }
                    self.status = .failed
                    self.lastError = "Нет ответа от ПК \(self.serverHost) — проверьте, что сервер запущен"
                }
            }
        }
        timer.resume()
        keepAliveTimer = timer
    }

    // MARK: - Приём обратной связи

    private func startFeedbackListener() {
        guard let port = NWEndpoint.Port(rawValue: feedbackPort) else { return }
        let listener = try? NWListener(using: .udp, on: port)
        self.listener = listener

        listener?.newConnectionHandler = { [weak self] peer in
            guard let self else { return }
            let key = ObjectIdentifier(peer)
            self.peers[key] = peer
            peer.stateUpdateHandler = { [weak self] state in
                if case .failed = state {
                    self?.peers[key] = nil
                }
            }
            peer.start(queue: self.queue)
            self.receive(from: peer)
        }
        listener?.start(queue: queue)
    }

    private func receive(from peer: NWConnection) {
        peer.receiveMessage { [weak self] data, _, _, error in
            if let data, !data.isEmpty {
                self?.handle(data: data)
            }
            if error == nil {
                self?.receive(from: peer)
            }
        }
    }

    private func handle(data: Data) {
        let bytes = [UInt8](data)
        guard bytes.count >= 4, bytes[0] == 0xF2, bytes[1] == 1 else { return }
        guard let kind = FeedbackMessage.Kind(rawValue: bytes[2]) else { return }

        // Длина полезной нагрузки объявлена в заголовке — режем по ней,
        // чтобы лишние байты в датаграмме не попали в разбор.
        let declared = Int(bytes[3])
        let end = min(bytes.count, 4 + declared)
        let payload = Data(bytes[4..<end])

        lastAnswerUtc = Date()

        DispatchQueue.main.async {
            self.onFeedback?(FeedbackMessage(kind: kind, payload: payload))
        }
    }
}
