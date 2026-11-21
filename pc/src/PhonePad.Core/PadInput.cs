namespace PhonePad.Core;

/// <summary>
/// Нормализованное состояние ввода, готовое к отправке в виртуальный пад.
/// Оси — в диапазоне −32768..32767, как их ожидает XInput.
/// </summary>
public struct PadInput
{
    /// <summary>Нажатые кнопки (внутренний формат, не зависит от бэкенда).</summary>
    public PadButtons Buttons;

    public short LeftX;
    public short LeftY;
    public short RightX;
    public short RightY;
    public byte LeftTrigger;
    public byte RightTrigger;

    public static PadInput FromState(GamepadState state)
    {
        return new PadInput
        {
            Buttons = state.Buttons,
            LeftX = Scale(state.LeftX),
            LeftY = Scale(state.LeftY),
            RightX = Scale(state.RightX),
            RightY = Scale(state.RightY),
            LeftTrigger = state.LeftTrigger,
            RightTrigger = state.RightTrigger
        };
    }

    /// <summary>−1000..1000 → −32768..32767.</summary>
    private static short Scale(short value)
    {
        double scaled = value / 1000.0 * 32767.0;
        return (short)Math.Clamp(Math.Round(scaled), short.MinValue, short.MaxValue);
    }
}

/// <summary>Раскладка битов кнопок XUSB (Xbox 360 controller).</summary>
public static class XusbButtons
{
    public const ushort DPadUp = 0x0001;
    public const ushort DPadDown = 0x0002;
    public const ushort DPadLeft = 0x0004;
    public const ushort DPadRight = 0x0008;
    public const ushort Start = 0x0010;
    public const ushort Back = 0x0020;
    public const ushort LeftThumb = 0x0040;
    public const ushort RightThumb = 0x0080;
    public const ushort LeftShoulder = 0x0100;
    public const ushort RightShoulder = 0x0200;
    public const ushort Guide = 0x0400;
    public const ushort A = 0x0800;
    public const ushort B = 0x1000;
    public const ushort X = 0x2000;
    public const ushort Y = 0x4000;

    public static ushort FromPadButtons(PadButtons buttons)
    {
        ushort result = 0;

        if (buttons.Has(PadButtons.DPadUp)) result |= DPadUp;
        if (buttons.Has(PadButtons.DPadDown)) result |= DPadDown;
        if (buttons.Has(PadButtons.DPadLeft)) result |= DPadLeft;
        if (buttons.Has(PadButtons.DPadRight)) result |= DPadRight;
        if (buttons.Has(PadButtons.Start)) result |= Start;
        if (buttons.Has(PadButtons.Back)) result |= Back;
        if (buttons.Has(PadButtons.LeftThumb)) result |= LeftThumb;
        if (buttons.Has(PadButtons.RightThumb)) result |= RightThumb;
        if (buttons.Has(PadButtons.LeftShoulder)) result |= LeftShoulder;
        if (buttons.Has(PadButtons.RightShoulder)) result |= RightShoulder;
        if (buttons.Has(PadButtons.Guide)) result |= Guide;
        if (buttons.Has(PadButtons.A)) result |= A;
        if (buttons.Has(PadButtons.B)) result |= B;
        if (buttons.Has(PadButtons.X)) result |= X;
        if (buttons.Has(PadButtons.Y)) result |= Y;

        return result;
    }
}
