namespace PhonePad.Core;

/// <summary>Биты кнопок в проводном протоколе (см. docs/PROTOCOL.md).</summary>
[Flags]
public enum PadButtons : ushort
{
    None = 0,
    DPadUp = 1 << 0,
    DPadDown = 1 << 1,
    DPadLeft = 1 << 2,
    DPadRight = 1 << 3,
    LeftShoulder = 1 << 4,
    RightShoulder = 1 << 5,
    Back = 1 << 6,
    Start = 1 << 7,
    LeftThumb = 1 << 8,
    RightThumb = 1 << 9,
    Guide = 1 << 10,
    Mute = 1 << 11,
    A = 1 << 12,
    B = 1 << 13,
    X = 1 << 14,
    Y = 1 << 15
}

/// <summary>Тип входящего пакета «телефон → ПК».</summary>
public enum InputPacketType : byte
{
    State = 1,
    Hello = 2,
    Goodbye = 3,
    Ping = 4
}

/// <summary>Полный снимок состояния управления.</summary>
public struct GamepadState
{
    public PadButtons Buttons;
    public byte LeftTrigger;
    public byte RightTrigger;

    /// <summary>Ось стика: −1000..1000.</summary>
    public short LeftX;

    public short LeftY;
    public short RightX;
    public short RightY;

    /// <summary>Гироскоп: сотые градуса в секунду.</summary>
    public short GyroPitch;

    public short GyroRoll;

    public ushort Sequence;

    public DateTime ReceivedUtc;

    public static GamepadState Empty => new()
    {
        Buttons = PadButtons.None,
        ReceivedUtc = DateTime.UtcNow
    };

    public bool Has(PadButtons button) => (Buttons & button) == button;
}

/// <summary>Вспомогательные операции над маской кнопок.</summary>
public static class PadButtonsExtensions
{
    public static bool Has(this PadButtons buttons, PadButtons flag) => (buttons & flag) == flag;
}
