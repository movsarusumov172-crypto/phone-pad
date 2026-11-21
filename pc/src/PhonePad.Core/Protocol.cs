using System.Buffers.Binary;

namespace PhonePad.Core;

/// <summary>Типы сообщений «ПК → телефон».</summary>
public enum FeedbackType : byte
{
    /// <summary>Классический rumble: два мотора. payload: u8 left, u8 right, u16 durationMs.</summary>
    Rumble = 1,

    /// <summary>Две полосы «кузова»: payload: u8 lowStrength, u8 lowFreq, u8 highStrength, u8 highFreq, u16 durationMs.</summary>
    Body = 2,

    /// <summary>Адаптивный триггер (имитация сопротивления): payload: u8 lt, u8 rt, u16 durationMs.</summary>
    Trigger = 3,

    /// <summary>Звук: payload: u8 soundId, u8 param.</summary>
    Sound = 4,

    /// <summary>HUD: u16 speedKmh, u8 gear, u16 rpm, i16 lateralG×100, u8 throttle, u8 brake, u8 slip, u8 flags.</summary>
    Hud = 5,

    /// <summary>Подсветка: payload: u8 r, u8 g, u8 b.</summary>
    Led = 6,

    /// <summary>Статус: payload: u8 code, u8 detail.</summary>
    Status = 7
}

/// <summary>Идентификаторы звуков.</summary>
public static class SoundIds
{
    public const byte ButtonClick = 1;
    public const byte GearShift = 2;
    public const byte Startup = 3;
    public const byte Collision = 4;
    public const byte AbsPulse = 5;
    public const byte SurfaceChange = 6;
}

/// <summary>Кодирование и декодирование проводного протокола.</summary>
public static class Protocol
{
    public const byte InputMagic = 0xF1;
    public const byte FeedbackMagic = 0xF2;
    public const byte Version = 1;
    public const int InputPacketSize = 23;
    public const int FeedbackHeaderSize = 4;

    // --- Ввод: телефон → ПК -------------------------------------------------

    public static byte[] EncodeState(GamepadState state, bool gyroActive = false)
    {
        var buf = new byte[InputPacketSize];
        buf[0] = InputMagic;
        buf[1] = Version;
        buf[2] = (byte)InputPacketType.State;
        buf[3] = gyroActive ? (byte)1 : (byte)0;
        BinaryPrimitives.WriteUInt16LittleEndian(buf.AsSpan(4), (ushort)state.Buttons);
        buf[6] = state.LeftTrigger;
        buf[7] = state.RightTrigger;
        BinaryPrimitives.WriteInt16LittleEndian(buf.AsSpan(8), state.LeftX);
        BinaryPrimitives.WriteInt16LittleEndian(buf.AsSpan(10), state.LeftY);
        BinaryPrimitives.WriteInt16LittleEndian(buf.AsSpan(12), state.RightX);
        BinaryPrimitives.WriteInt16LittleEndian(buf.AsSpan(14), state.RightY);
        BinaryPrimitives.WriteInt16LittleEndian(buf.AsSpan(16), state.GyroPitch);
        BinaryPrimitives.WriteInt16LittleEndian(buf.AsSpan(18), state.GyroRoll);
        BinaryPrimitives.WriteUInt16LittleEndian(buf.AsSpan(20), state.Sequence);
        buf[22] = Crc8(buf.AsSpan(0, 22));
        return buf;
    }

    public static byte[] EncodeControl(InputPacketType type)
    {
        var buf = new byte[InputPacketSize];
        buf[0] = InputMagic;
        buf[1] = Version;
        buf[2] = (byte)type;
        buf[22] = Crc8(buf.AsSpan(0, 22));
        return buf;
    }

    public static bool TryDecodeInput(ReadOnlySpan<byte> data, out InputPacketType type, out GamepadState state)
    {
        type = InputPacketType.State;
        state = GamepadState.Empty;

        if (data.Length < InputPacketSize || data[0] != InputMagic || data[1] != Version)
        {
            return false;
        }

        if (data[22] != Crc8(data[..22]))
        {
            return false;
        }

        type = (InputPacketType)data[2];
        if (!Enum.IsDefined(typeof(InputPacketType), type))
        {
            // Неизвестный тип пакета: CRC сошёлся, значит это пакет другой
            // версии протокола — молча игнорируем.
            return false;
        }

        state.Buttons = (PadButtons)BinaryPrimitives.ReadUInt16LittleEndian(data[4..]);
        state.LeftTrigger = data[6];
        state.RightTrigger = data[7];
        state.LeftX = BinaryPrimitives.ReadInt16LittleEndian(data[8..]);
        state.LeftY = BinaryPrimitives.ReadInt16LittleEndian(data[10..]);
        state.RightX = BinaryPrimitives.ReadInt16LittleEndian(data[12..]);
        state.RightY = BinaryPrimitives.ReadInt16LittleEndian(data[14..]);
        state.GyroPitch = BinaryPrimitives.ReadInt16LittleEndian(data[16..]);
        state.GyroRoll = BinaryPrimitives.ReadInt16LittleEndian(data[18..]);
        state.Sequence = BinaryPrimitives.ReadUInt16LittleEndian(data[20..]);
        state.ReceivedUtc = DateTime.UtcNow;
        return true;
    }

    // --- Обратная связь: ПК → телефон --------------------------------------

    public static byte[] EncodeFeedback(FeedbackType type, ReadOnlySpan<byte> payload)
    {
        if (payload.Length > byte.MaxValue)
        {
            throw new ArgumentOutOfRangeException(
                nameof(payload),
                payload.Length,
                "Полезная нагрузка обратной связи не может быть длиннее 255 байт");
        }

        var buf = new byte[FeedbackHeaderSize + payload.Length];
        buf[0] = FeedbackMagic;
        buf[1] = Version;
        buf[2] = (byte)type;
        buf[3] = (byte)payload.Length;
        payload.CopyTo(buf.AsSpan(FeedbackHeaderSize));
        return buf;
    }

    public static bool TryDecodeFeedback(ReadOnlySpan<byte> data, out FeedbackType type, out byte[] payload)
    {
        type = FeedbackType.Status;
        payload = Array.Empty<byte>();

        if (data.Length < FeedbackHeaderSize || data[0] != FeedbackMagic || data[1] != Version)
        {
            return false;
        }

        int len = data[3];
        if (data.Length < FeedbackHeaderSize + len)
        {
            return false;
        }

        type = (FeedbackType)data[2];
        payload = data.Slice(FeedbackHeaderSize, len).ToArray();
        return true;
    }

    // --- Вспомогательное ---------------------------------------------------

    /// <summary>CRC-8/ATM: полином 0x07, init 0x00, без отражения.</summary>
    public static byte Crc8(ReadOnlySpan<byte> data)
    {
        byte crc = 0;
        foreach (byte b in data)
        {
            crc ^= b;
            for (int i = 0; i < 8; i++)
            {
                crc = (byte)((crc & 0x80) != 0 ? (crc << 1) ^ 0x07 : crc << 1);
            }
        }

        return crc;
    }

    /// <summary>
    /// Проверяет, что счётчик пакетов новее предыдущего, с учётом переполнения
    /// u16 (счётчик проходит 65535 → 0).
    /// </summary>
    public static bool IsNewerSequence(ushort sequence, ushort last)
    {
        short diff = (short)(sequence - last);
        return diff > 0;
    }
}
