using PhonePad.Core;

namespace PhonePad.Server;

/// <summary>Абстракция виртуального игрового пада: Xbox 360 (XInput) или консольный эмулятор.</summary>
public interface IVirtualPad : IDisposable
{
    /// <summary>Человекочитаемое имя бэкенда для логов.</summary>
    string Description { get; }

    /// <summary>Применяет снимок ввода и отправляет отчёт в игру.</summary>
    void Apply(PadInput input);

    /// <summary>Событие: игра заказала вибрацию (large, small) — значения 0..255.</summary>
    event Action<byte, byte>? RumbleReceived;
}

/// <summary>Бэкенд без драйвера: печатает состояние в консоль. Нужен для отладки и для Linux/macOS.</summary>
public sealed class ConsolePad : IVirtualPad
{
    private PadInput _last;
    private bool _hasLast;

    public ConsolePad(Action<string>? logger = null)
    {
        Logger = logger ?? Console.WriteLine;
    }

    private Action<string> Logger { get; }

    public string Description => "консольный (виртуальный пад не создаётся)";

    public event Action<byte, byte>? RumbleReceived;

    public void Apply(PadInput input)
    {
        if (_hasLast && _last.Equals(input))
        {
            return;
        }

        _hasLast = true;
        _last = input;

        Logger($"[pad] buttons={input.Buttons} lt={input.LeftTrigger} rt={input.RightTrigger} " +
               $"lx={input.LeftX} ly={input.LeftY} rx={input.RightX} ry={input.RightY}");
    }

    public void Dispose()
    {
    }
}
