using Nefarius.ViGEm.Client;
using Nefarius.ViGEm.Client.Targets;
using Nefarius.ViGEm.Client.Targets.Xbox360;
using PhonePad.Core;

namespace PhonePad.Server;

/// <summary>
/// Виртуальный контроллер Xbox 360 через драйвер ViGEmBus.
/// Игра (в том числе Forza Horizon 6 из Xbox app / Microsoft Store) видит обычный XInput-пад.
/// </summary>
public sealed class VigemPad : IVirtualPad
{
    private readonly ViGEmClient _client;
    private readonly IXbox360Controller _pad;

    public VigemPad()
    {
        // Конструктор подключается к шине ViGEmBus; если драйвер не установлен — исключение.
        _client = new ViGEmClient();
        _pad = _client.CreateXbox360Controller();
        _pad.AutoSubmitReport = false;
        _pad.Connect();
        _pad.FeedbackReceived += OnFeedbackReceived;
    }

    public string Description => "виртуальный Xbox 360 (ViGEmBus, XInput)";

    public event Action<byte, byte>? RumbleReceived;

    private void OnFeedbackReceived(object? sender, Xbox360FeedbackReceivedEventArgs e)
    {
        RumbleReceived?.Invoke(e.LargeMotor, e.SmallMotor);
    }

    public void Apply(PadInput input)
    {
        // Маску собираем из значений библиотеки, чтобы не расходиться с её раскладкой.
        ushort mask = 0;
        var b = input.Buttons;

        if (b.Has(PadButtons.DPadUp)) mask |= Xbox360Button.Up.Value;
        if (b.Has(PadButtons.DPadDown)) mask |= Xbox360Button.Down.Value;
        if (b.Has(PadButtons.DPadLeft)) mask |= Xbox360Button.Left.Value;
        if (b.Has(PadButtons.DPadRight)) mask |= Xbox360Button.Right.Value;
        if (b.Has(PadButtons.Start)) mask |= Xbox360Button.Start.Value;
        if (b.Has(PadButtons.Back)) mask |= Xbox360Button.Back.Value;
        if (b.Has(PadButtons.LeftThumb)) mask |= Xbox360Button.LeftThumb.Value;
        if (b.Has(PadButtons.RightThumb)) mask |= Xbox360Button.RightThumb.Value;
        if (b.Has(PadButtons.LeftShoulder)) mask |= Xbox360Button.LeftShoulder.Value;
        if (b.Has(PadButtons.RightShoulder)) mask |= Xbox360Button.RightShoulder.Value;
        if (b.Has(PadButtons.Guide)) mask |= Xbox360Button.Guide.Value;
        if (b.Has(PadButtons.A)) mask |= Xbox360Button.A.Value;
        if (b.Has(PadButtons.B)) mask |= Xbox360Button.B.Value;
        if (b.Has(PadButtons.X)) mask |= Xbox360Button.X.Value;
        if (b.Has(PadButtons.Y)) mask |= Xbox360Button.Y.Value;

        _pad.SetButtonsFull(mask);
        _pad.LeftTrigger = input.LeftTrigger;
        _pad.RightTrigger = input.RightTrigger;
        _pad.LeftThumbX = input.LeftX;
        _pad.LeftThumbY = input.LeftY;
        _pad.RightThumbX = input.RightX;
        _pad.RightThumbY = input.RightY;
        _pad.SubmitReport();
    }

    public void Dispose()
    {
        try
        {
            _pad.Disconnect();
        }
        catch
        {
            // игнорируем: пад уже мог быть отключён драйвером
        }

        _client.Dispose();
    }
}
