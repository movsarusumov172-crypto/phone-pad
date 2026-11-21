import Foundation

/// Битовая маска кнопок — совпадает с PROTOCOL.md.
enum Btn {
    static let dpadUp: UInt16    = 1 << 0
    static let dpadDown: UInt16  = 1 << 1
    static let dpadLeft: UInt16  = 1 << 2
    static let dpadRight: UInt16 = 1 << 3
    static let lb: UInt16        = 1 << 4
    static let rb: UInt16        = 1 << 5
    static let back: UInt16      = 1 << 6
    static let start: UInt16     = 1 << 7
    static let l3: UInt16        = 1 << 8
    static let r3: UInt16        = 1 << 9
    static let guide: UInt16     = 1 << 10
    static let mute: UInt16      = 1 << 11
    static let a: UInt16         = 1 << 12
    static let b: UInt16         = 1 << 13
    static let x: UInt16         = 1 << 14
    static let y: UInt16         = 1 << 15
}

/// Полный снимок состояния управления (ровно то, что уходит по сети).
struct PadState {
    var buttons: UInt16 = 0
    var leftTrigger: UInt8 = 0
    var rightTrigger: UInt8 = 0
    var leftX: Int16 = 0
    var leftY: Int16 = 0
    var rightX: Int16 = 0
    var rightY: Int16 = 0
    var gyroPitch: Int16 = 0
    var gyroRoll: Int16 = 0

    mutating func clearAll() {
        buttons = 0
        leftTrigger = 0
        rightTrigger = 0
        leftX = 0
        leftY = 0
        rightX = 0
        rightY = 0
    }
}

/// Кодирование пакета ввода (23 байта, little-endian) — см. docs/PROTOCOL.md.
enum WireFormat {
    static let inputMagic: UInt8 = 0xF1
    static let version: UInt8 = 1

    enum PacketType: UInt8 {
        case state = 1
        case hello = 2
        case goodbye = 3
        case ping = 4
    }

    static func crc8(_ data: [UInt8]) -> UInt8 {
        var crc: UInt8 = 0
        for byte in data {
            crc ^= byte
            for _ in 0..<8 {
                crc = (crc & 0x80) != 0 ? (crc << 1) ^ 0x07 : (crc << 1)
            }
        }
        return crc
    }

    static func encode(state: PadState, sequence: UInt16, gyroActive: Bool) -> Data {
        var body = [UInt8](repeating: 0, count: 22)
        body[0] = inputMagic
        body[1] = version
        body[2] = PacketType.state.rawValue
        body[3] = gyroActive ? 1 : 0
        writeU16(state.buttons, into: &body, at: 4)
        body[6] = state.leftTrigger
        body[7] = state.rightTrigger
        writeI16(state.leftX, into: &body, at: 8)
        writeI16(state.leftY, into: &body, at: 10)
        writeI16(state.rightX, into: &body, at: 12)
        writeI16(state.rightY, into: &body, at: 14)
        writeI16(state.gyroPitch, into: &body, at: 16)
        writeI16(state.gyroRoll, into: &body, at: 18)
        writeU16(sequence, into: &body, at: 20)
        let checksum = crc8(body)
        body.append(checksum)
        return Data(body)
    }

    static func encodeControl(_ type: PacketType) -> Data {
        var body = [UInt8](repeating: 0, count: 22)
        body[0] = inputMagic
        body[1] = version
        body[2] = type.rawValue
        let checksum = crc8(body)
        body.append(checksum)
        return Data(body)
    }

    // MARK: - вспомогательное

    private static func writeU16(_ value: UInt16, into bytes: inout [UInt8], at offset: Int) {
        bytes[offset] = UInt8(value & 0xFF)
        bytes[offset + 1] = UInt8((value >> 8) & 0xFF)
    }

    private static func writeI16(_ value: Int16, into bytes: inout [UInt8], at offset: Int) {
        let raw = UInt16(bitPattern: value)
        writeU16(raw, into: &bytes, at: offset)
    }
}
