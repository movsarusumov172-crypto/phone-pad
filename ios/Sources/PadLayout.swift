import UIKit

enum StickAxis {
    case left
    case right
}

enum ControlKind: Equatable {
    /// Кнопка с битовой маской.
    case button(mask: UInt16)
    /// Аналоговый триггер (ползунок). true — левый (LT/тормоз).
    case trigger(isLeft: Bool)
    /// Аналоговый стик.
    case stick(axis: StickAxis, floating: Bool)
}

/// Элемент раскладки. `frame` задан в нормализованных координатах (0…1), начало — левый верхний угол.
struct PadControl: Identifiable, Equatable {
    let id: String
    let kind: ControlKind
    let frame: CGRect
    let label: String
    var isRound: Bool = false
    /// Радиус стика в нормализованных единицах (по короткой стороне экрана).
    var stickRadius: CGFloat = 0.10
}

enum PadLayoutKind: String, CaseIterable, Identifiable {
    case full = "Полная (DualSense)"
    case racing = "Гонки"

    var id: String { rawValue }
}

enum PadLayout {
    /// Полная раскладка: стики, D-pad, крестовина, бамперы, триггеры-ползунки.
    static let full: [PadControl] = [
        // Левый стик
        PadControl(id: "ls", kind: .stick(axis: .left, floating: true),
                   frame: CGRect(x: 0.05, y: 0.40, width: 0.20, height: 0.34),
                   label: "L", isRound: true, stickRadius: 0.085),
        // D-pad (четыре отдельные зоны — надёжнее, чем анализ диагоналей)
        PadControl(id: "dpad_up", kind: .button(mask: Btn.dpadUp),
                   frame: CGRect(x: 0.05, y: 0.28, width: 0.07, height: 0.07), label: "▲"),
        PadControl(id: "dpad_down", kind: .button(mask: Btn.dpadDown),
                   frame: CGRect(x: 0.05, y: 0.14, width: 0.07, height: 0.07), label: "▼"),
        PadControl(id: "dpad_left", kind: .button(mask: Btn.dpadLeft),
                   frame: CGRect(x: 0.005, y: 0.21, width: 0.07, height: 0.07), label: "◀"),
        PadControl(id: "dpad_right", kind: .button(mask: Btn.dpadRight),
                   frame: CGRect(x: 0.095, y: 0.21, width: 0.07, height: 0.07), label: "▶"),

        // Правый стик
        PadControl(id: "rs", kind: .stick(axis: .right, floating: true),
                   frame: CGRect(x: 0.75, y: 0.06, width: 0.20, height: 0.34),
                   label: "R", isRound: true, stickRadius: 0.085),

        // Крестовина (Y сверху, X слева, B справа, A снизу — раскладка Xbox)
        PadControl(id: "btn_y", kind: .button(mask: Btn.y),
                   frame: CGRect(x: 0.855, y: 0.40, width: 0.075, height: 0.075),
                   label: "Y", isRound: true),
        PadControl(id: "btn_x", kind: .button(mask: Btn.x),
                   frame: CGRect(x: 0.775, y: 0.475, width: 0.075, height: 0.075),
                   label: "X", isRound: true),
        PadControl(id: "btn_b", kind: .button(mask: Btn.b),
                   frame: CGRect(x: 0.935, y: 0.475, width: 0.075, height: 0.075),
                   label: "B", isRound: true),
        PadControl(id: "btn_a", kind: .button(mask: Btn.a),
                   frame: CGRect(x: 0.855, y: 0.55, width: 0.075, height: 0.075),
                   label: "A", isRound: true),

        // Бамперы
        PadControl(id: "lb", kind: .button(mask: Btn.lb),
                   frame: CGRect(x: 0.27, y: 0.02, width: 0.14, height: 0.08), label: "LB"),
        PadControl(id: "rb", kind: .button(mask: Btn.rb),
                   frame: CGRect(x: 0.59, y: 0.02, width: 0.14, height: 0.08), label: "RB"),

        // Триггеры — вертикальные ползунки по краям экрана
        PadControl(id: "lt", kind: .trigger(isLeft: true),
                   frame: CGRect(x: 0.0, y: 0.12, width: 0.045, height: 0.76), label: "LT"),
        PadControl(id: "rt", kind: .trigger(isLeft: false),
                   frame: CGRect(x: 0.955, y: 0.12, width: 0.045, height: 0.76), label: "RT"),

        // Start / Back / Guide
        PadControl(id: "back", kind: .button(mask: Btn.back),
                   frame: CGRect(x: 0.42, y: 0.02, width: 0.06, height: 0.07), label: "≡"),
        PadControl(id: "start", kind: .button(mask: Btn.start),
                   frame: CGRect(x: 0.52, y: 0.02, width: 0.06, height: 0.07), label: "▷"),
        PadControl(id: "guide", kind: .button(mask: Btn.guide),
                   frame: CGRect(x: 0.47, y: 0.10, width: 0.06, height: 0.06), label: "PS", isRound: true)
    ]

    /// Раскладка для гонок: крупные педали, руль (тач или гироскоп), минимум кнопок.
    static let racing: [PadControl] = [
        // Зона руля: плавающий стик в левой половине
        PadControl(id: "ls", kind: .stick(axis: .left, floating: true),
                   frame: CGRect(x: 0.03, y: 0.12, width: 0.40, height: 0.80),
                   label: "РУЛЬ", isRound: true, stickRadius: 0.16),

        // Педали: тормоз ближе к центру, газ — на самом краю (как у настоящего
        // контроллера: правый большой палец нажимает газ краем ладони).
        PadControl(id: "lt", kind: .trigger(isLeft: true),
                   frame: CGRect(x: 0.72, y: 0.12, width: 0.11, height: 0.80), label: "ТОРМ"),
        PadControl(id: "rt", kind: .trigger(isLeft: false),
                   frame: CGRect(x: 0.86, y: 0.12, width: 0.11, height: 0.80), label: "ГАЗ"),

        // Кнопки
        PadControl(id: "btn_a", kind: .button(mask: Btn.a),
                   frame: CGRect(x: 0.55, y: 0.58, width: 0.12, height: 0.12),
                   label: "A", isRound: true),
        PadControl(id: "btn_b", kind: .button(mask: Btn.b),
                   frame: CGRect(x: 0.55, y: 0.42, width: 0.12, height: 0.12),
                   label: "B", isRound: true),
        PadControl(id: "lb", kind: .button(mask: Btn.lb),
                   frame: CGRect(x: 0.55, y: 0.26, width: 0.12, height: 0.12),
                   label: "HB", isRound: true),
        PadControl(id: "rb", kind: .button(mask: Btn.rb),
                   frame: CGRect(x: 0.55, y: 0.10, width: 0.12, height: 0.12),
                   label: "RST", isRound: true),
        PadControl(id: "start", kind: .button(mask: Btn.start),
                   frame: CGRect(x: 0.55, y: 0.78, width: 0.12, height: 0.12), label: "≡")
    ]

    static func controls(for kind: PadLayoutKind) -> [PadControl] {
        switch kind {
        case .full: return full
        case .racing: return racing
        }
    }
}
