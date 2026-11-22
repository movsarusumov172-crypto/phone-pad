import SwiftUI
import UIKit

/// Хранилище состояния пада, которым управляет жестовая область.
final class PadController: ObservableObject {
    @Published var state = PadState()
    @Published var layoutKind: PadLayoutKind = .full
    @Published var gyroEnabled = false

    /// Вызывается при нажатии любой кнопки — используется для тактильного отклика.
    var onButtonPress: (() -> Void)?

    private let lock = NSLock()
    private var rawState = PadState()

    /// Актуальное состояние (безопасно читать из фонового потока отправки).
    var currentState: PadState {
        lock.lock()
        defer { lock.unlock() }
        return rawState
    }

    /// Единственная точка записи состояния: обновляет и потокобезопасный снимок,
    /// и публикуемое значение для SwiftUI. Вызывать только из setState —
    /// прямая запись в `state` оставляет `rawState` stale, и сетевой цикл
    /// отправки начинает слать устаревший ввод.
    func setState(_ newState: PadState) {
        lock.lock()
        rawState = newState
        lock.unlock()
        if Thread.isMainThread {
            state = newState
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.state = newState
            }
        }
    }

    /// Сбросить всё (например, при сворачивании приложения) — иначе в игре
    /// остаются зажатыми газ и кнопки.
    func reset() {
        var empty = PadState()
        empty.clearAll()
        setState(empty)
    }
}

/// SwiftUI-обёртка над UIKit-вью с мультитачем.
struct PadView: UIViewRepresentable {
    @ObservedObject var controller: PadController

    func makeUIView(context: Context) -> PadTouchView {
        let view = PadTouchView()
        view.isMultipleTouchEnabled = true
        view.backgroundColor = .clear
        view.onStateChanged = { [weak controller] state in
            controller?.setState(state)
        }
        view.onButtonPress = { [weak controller] in
            controller?.onButtonPress?()
        }
        view.apply(layout: controller.layoutKind)
        return view
    }

    func updateUIView(_ uiView: PadTouchView, context: Context) {
        // Важно: идём через setState, а не напрямую в `state` — иначе
        // потокобезопасный снимок rawState останется старым и сетевой цикл
        // отправки будет слать устаревшее состояние пада.
        uiView.onStateChanged = { [weak controller] state in
            controller?.setState(state)
        }
        uiView.onButtonPress = { [weak controller] in
            controller?.onButtonPress?()
        }
        uiView.apply(layout: controller.layoutKind)
    }
}

/// Экран пада: рисует раскладку и обрабатывает касания (до 10 пальцев).
final class PadTouchView: UIView {
    var onStateChanged: ((PadState) -> Void)?
    var onButtonPress: (() -> Void)?

    private struct Binding {
        let controlId: String
        let kind: ControlKind
        let startPoint: CGPoint
        var stickOrigin: CGPoint?
    }

    private var controls: [PadControl] = []
    private var frames: [String: CGRect] = [:]
    private var stickRadii: [String: CGFloat] = [:]
    private var bindings: [ObjectIdentifier: Binding] = [:]
    private var pressed: Set<String> = []
    private var stickOrigins: [String: CGPoint] = [:]
    private var stickOffsets: [String: CGPoint] = [:]
    private var triggerValues: [String: CGFloat] = [:]

    private var state = PadState()

    /// Полоса сверху, которую занимает панель статуса приложения.
    /// Элементы пада не должны под неё заезжать — иначе кнопки «HB»/«RST»
    /// прячутся под HUD.
    var topReserved: CGFloat = 58

    func apply(layout kind: PadLayoutKind) {
        let newControls = PadLayout.controls(for: kind)
        // Сравниваем раскладки целиком, а не только идентификаторы: смена
        // радиуса стика или подписи тоже должна перерисовать экран.
        guard newControls != controls else { return }
        controls = newControls
        releaseAll()
        setNeedsDisplay()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        frames.removeAll(keepingCapacity: true)
        stickRadii.removeAll(keepingCapacity: true)

        // Верхняя полоса резервируется под панель статуса, остальное место
        // делится между элементами пада.
        let top = min(bounds.height * 0.5, max(0, topReserved))
        let usableHeight = max(1, bounds.height - top)
        let shortSide = min(bounds.width, usableHeight)

        for control in controls {
            let rect = CGRect(
                x: control.frame.minX * bounds.width,
                y: top + control.frame.minY * usableHeight,
                width: control.frame.width * bounds.width,
                height: control.frame.height * usableHeight)
            frames[control.id] = rect
            stickRadii[control.id] = control.stickRadius * shortSide
        }
    }

    // MARK: - Обработка касаний

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let point = touch.location(in: self)
            guard let control = control(at: point) else { continue }

            let binding = Binding(controlId: control.id,
                                  kind: control.kind,
                                  startPoint: point,
                                  stickOrigin: nil)
            bindings[ObjectIdentifier(touch)] = binding

            switch control.kind {
            case .button(let mask):
                state.buttons |= mask
                pressed.insert(control.id)
                onButtonPress?()

            case .trigger(let isLeft):
                triggerValues[control.id] = 0
                updateTrigger(control, at: point)

            case .stick(let axis, let floating):
                let origin: CGPoint
                if floating {
                    origin = point
                } else {
                    origin = CGPoint(x: frames[control.id]?.midX ?? 0,
                                     y: frames[control.id]?.midY ?? 0)
                }
                stickOrigins[control.id] = origin
                stickOffsets[control.id] = .zero
                updateStick(control, at: point)
            }

            setNeedsDisplay()
        }
        publish()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let key = ObjectIdentifier(touch)
            guard var binding = bindings[key] else { continue }
            let point = touch.location(in: self)

            switch binding.kind {
            case .button:
                // «Съезд» с кнопки отпускает её — как на настоящем контроллере.
                if let rect = frames[binding.controlId], !rect.insetBy(dx: -12, dy: -12).contains(point) {
                    release(key: key, binding: binding)
                    continue
                }

            case .trigger:
                updateTrigger(control(for: binding.controlId), at: point)

            case .stick:
                updateStick(control(for: binding.controlId), at: point)
            }

            bindings[key] = binding
            setNeedsDisplay()
        }
        publish()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            release(key: ObjectIdentifier(touch),
                    binding: bindings[ObjectIdentifier(touch)])
        }
        publish()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }

    private func release(key: ObjectIdentifier, binding: Binding?) {
        guard let binding else { return }
        bindings.removeValue(forKey: key)

        switch binding.kind {
        case .button(let mask):
            state.buttons &= ~mask
            pressed.remove(binding.controlId)

        case .trigger(let isLeft):
            // Обнуляем только тот триггер, который отпустили: иначе отпускание
            // одного пальца сбрасывало бы и второй (двигатель «залипал» на нуле).
            triggerValues[binding.controlId] = 0
            if isLeft {
                state.leftTrigger = 0
            } else {
                state.rightTrigger = 0
            }

        case .stick(let axis, _):
            // То же со стиками: левый не должен обнулять правый.
            stickOrigins[binding.controlId] = nil
            stickOffsets[binding.controlId] = .zero
            switch axis {
            case .left:
                state.leftX = 0
                state.leftY = 0
            case .right:
                state.rightX = 0
                state.rightY = 0
            }
        }
        setNeedsDisplay()
    }

    private func releaseAll() {
        for (key, binding) in Array(bindings) {
            release(key: key, binding: binding)
        }
        bindings.removeAll()
        pressed.removeAll()
        triggerValues.removeAll()
        stickOrigins.removeAll()
        stickOffsets.removeAll()
        state.clearAll()
        publish()
    }

    private func control(for id: String) -> PadControl? {
        controls.first { $0.id == id }
    }

    private func control(at point: CGPoint) -> PadControl? {
        // Выбираем самый маленький элемент под точкой — так кнопки поверх стиков перехватывают касания.
        let hits = controls.filter { control in
            guard let rect = frames[control.id] else { return false }
            return rect.insetBy(dx: -8, dy: -8).contains(point)
        }
        return hits.min { lhs, rhs in
            let lr = frames[lhs.id]!.width * frames[lhs.id]!.height
            let rr = frames[rhs.id]!.width * frames[rhs.id]!.height
            return lr < rr
        }
    }

    private func updateTrigger(_ control: PadControl?, at point: CGPoint) {
        guard let control, let rect = frames[control.id] else { return }
        let fraction = (point.y - rect.minY) / max(1, rect.height)
        let clamped = max(0, min(1, fraction))
        triggerValues[control.id] = clamped
        let value = UInt8(clamped * 255)
        if case .trigger(let isLeft) = control.kind {
            if isLeft {
                state.leftTrigger = value
            } else {
                state.rightTrigger = value
            }
        }
    }

    private func updateStick(_ control: PadControl?, at point: CGPoint) {
        guard let control, let origin = stickOrigins[control.id] else { return }
        let radius = max(20, stickRadii[control.id] ?? 60)

        var dx = point.x - origin.x
        var dy = point.y - origin.y
        let distance = sqrt(dx * dx + dy * dy)
        if distance > radius {
            dx *= radius / distance
            dy *= radius / distance
        }
        stickOffsets[control.id] = CGPoint(x: dx, y: dy)

        let nx = max(-1, min(1, dx / radius))
        let ny = max(-1, min(1, dy / radius))
        let xValue = Int16(nx * 1000)
        let yValue = Int16(-ny * 1000) // экран Y растёт вниз, ось Y вверх

        if case .stick(let axis, _) = control.kind {
            switch axis {
            case .left:
                state.leftX = xValue
                state.leftY = yValue
            case .right:
                state.rightX = xValue
                state.rightY = yValue
            }
        }
    }

    private func publish() {
        onStateChanged?(state)
    }

    /// Внешняя установка (например, руление гироскопом): состояние контроллера без сенсорного ввода.
    func applyGyroSteering(x: Int16) {
        state.leftX = x
        publish()
    }

    // MARK: - Отрисовка

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        UIColor.black.withAlphaComponent(0.55).setFill()
        ctx.fill(rect)

        for control in controls {
            guard let frame = frames[control.id] else { continue }
            switch control.kind {
            case .button:
                drawButton(control, frame: frame)
            case .trigger:
                drawTrigger(control, frame: frame)
            case .stick:
                drawStick(control, frame: frame)
            }
        }
    }

    private func drawButton(_ control: PadControl, frame: CGRect) {
        let isPressed = pressed.contains(control.id)
        let path: UIBezierPath
        if control.isRound {
            path = UIBezierPath(ovalIn: frame)
        } else {
            path = UIBezierPath(roundedRect: frame, cornerRadius: min(10, frame.height / 3))
        }

        UIColor.white.withAlphaComponent(isPressed ? 0.55 : 0.16).setFill()
        path.fill()

        UIColor.white.withAlphaComponent(isPressed ? 0.95 : 0.35).setStroke()
        path.lineWidth = 1.5
        path.stroke()

        drawLabel(control.label, in: frame)
    }

    private func drawTrigger(_ control: PadControl, frame: CGRect) {
        let value = triggerValues[control.id] ?? 0

        let path = UIBezierPath(roundedRect: frame, cornerRadius: 8)
        UIColor.white.withAlphaComponent(0.10).setFill()
        path.fill()
        UIColor.white.withAlphaComponent(0.30).setStroke()
        path.lineWidth = 1.0
        path.stroke()

        // Ползунок заполняется снизу вверх — так он читается как педаль.
        if value > 0 {
            let height = frame.height * value
            let fill = CGRect(x: frame.minX, y: frame.maxY - height,
                              width: frame.width, height: height)
            UIColor.systemOrange.withAlphaComponent(0.55).setFill()
            UIBezierPath(roundedRect: fill, cornerRadius: 8).fill()
        }

        // Подпись — вверху ползунка, чтобы не перекрывалась заливкой.
        var labelFrame = frame
        labelFrame.origin.y = frame.minY
        labelFrame.size.height = min(22, frame.height * 0.2)
        drawLabel(control.label, in: labelFrame, maxFontSize: 15)
    }

    private func drawStick(_ control: PadControl, frame: CGRect) {
        // Контур зоны: по нему видно, где «живёт» руль, даже когда стик плавает.
        let zone = UIBezierPath(roundedRect: frame, cornerRadius: 18)
        UIColor.white.withAlphaComponent(0.05).setFill()
        zone.fill()
        UIColor.white.withAlphaComponent(0.12).setStroke()
        zone.lineWidth = 1.0
        zone.stroke()

        let origin = stickOrigins[control.id]
            ?? CGPoint(x: frames[control.id]?.midX ?? 0, y: frames[control.id]?.midY ?? 0)
        let radius = max(20, stickRadii[control.id] ?? 60)

        let circle = UIBezierPath(ovalIn: CGRect(x: origin.x - radius, y: origin.y - radius,
                                                width: radius * 2, height: radius * 2))
        UIColor.white.withAlphaComponent(0.14).setFill()
        circle.fill()
        UIColor.white.withAlphaComponent(0.32).setStroke()
        circle.lineWidth = 1.5
        circle.stroke()

        let offset = stickOffsets[control.id] ?? .zero
        let knob = UIBezierPath(ovalIn: CGRect(x: origin.x + offset.x - radius * 0.38,
                                               y: origin.y + offset.y - radius * 0.38,
                                               width: radius * 0.76, height: radius * 0.76))
        UIColor.white.withAlphaComponent(0.45).setFill()
        knob.fill()

        // Подпись зоны — мелко, в нижнем углу: сверху может лежать HUD,
        // а стик в любой точке зоны.
        var labelFrame = frame
        labelFrame.origin.y = frame.maxY - min(20, frame.height * 0.14)
        labelFrame.size.height = min(20, frame.height * 0.14)
        drawLabel(control.label, in: labelFrame, maxFontSize: 14)
    }

    /// Рисует подпись, которая гарантированно помещается в рамку:
    /// кегль ограничен сверху и при необходимости ужимается по ширине.
    private func drawLabel(_ text: String, in frame: CGRect, maxFontSize: CGFloat = 18) {
        guard !text.isEmpty, frame.width > 6, frame.height > 6 else { return }

        var size = max(9, min(maxFontSize, frame.height * 0.55))
        var attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: size, weight: .semibold),
            .foregroundColor: UIColor.white.withAlphaComponent(0.85)
        ]

        var textSize = (text as NSString).size(withAttributes: attributes)
        if textSize.width > frame.width {
            // Ужимаем под шрифт, чтобы текст не вылезал за края элемента.
            size = max(7, size * frame.width / textSize.width)
            attributes[.font] = UIFont.systemFont(ofSize: size, weight: .semibold)
            textSize = (text as NSString).size(withAttributes: attributes)
        }

        let origin = CGPoint(x: frame.midX - textSize.width / 2,
                             y: frame.midY - textSize.height / 2)
        (text as NSString).draw(at: origin, withAttributes: attributes)
    }
}
