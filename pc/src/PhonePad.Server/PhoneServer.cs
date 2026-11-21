using System.Buffers.Binary;
using System.Net;
using System.Net.Sockets;
using PhonePad.Core;

namespace PhonePad.Server;

/// <summary>Настройки сервера (appsettings.json + аргументы командной строки).</summary>
public sealed class ServerOptions
{
    public string ListenAddress { get; set; } = "0.0.0.0";

    /// <summary>Порт, на котором сервер ждёт ввод от телефона.</summary>
    public int InputPort { get; set; } = 8888;

    /// <summary>Порт на телефоне, куда сервер шлёт обратную связь.</summary>
    public int FeedbackPort { get; set; } = 8889;

    /// <summary>Порт, на котором сервер слушает телеметрию Forza Horizon 6 (Data Out).</summary>
    public int TelemetryPort { get; set; } = 5300;

    /// <summary>Частота отправки отчётов в игру.</summary>
    public int PadRateHz { get; set; } = 100;

    /// <summary>
    /// Через сколько миллисекунд без ввода считать, что телефон отвалился.
    /// Нужен, чтобы в игре не «залипал» газ: без этого пад остаётся в последнем
    /// состоянии навсегда.
    /// </summary>
    public int PhoneTimeoutMs { get; set; } = 500;

    public bool Verbose { get; set; }

    public HapticOptions Haptics { get; set; } = new();
}

/// <summary>
/// Ядро сервера: принимает ввод с телефона, кормит виртуальный пад, принимает телеметрию FH6
/// и отправляет обратно тактильные эффекты, звуки и HUD.
/// </summary>
public sealed class PhoneServer : IAsyncDisposable
{
    private readonly IVirtualPad _pad;
    private readonly ServerOptions _options;
    private readonly HapticSynth _synth;
    private readonly UdpClient _inputSocket;
    private readonly UdpClient _telemetrySocket;
    private readonly UdpClient _feedbackSocket;
    private readonly object _gate = new();

    private GamepadState _latest = GamepadState.Empty;
    private IPEndPoint? _phone;
    private ushort _lastSequence;
    private bool _haveSequence;
    private DateTime _lastHudUtc = DateTime.MinValue;
    private DateTime _lastInputUtc = DateTime.MinValue;
    private byte _lastRumbleLarge;
    private byte _lastRumbleSmall;

    /// <summary>Были ли отправлены непустые полосы/триггеры — нужно, чтобы один раз
    /// отправить «стоп», когда эффект закончился (иначе телефон вибрирует вечно).</summary>
    private bool _bodyActive;
    private bool _triggersActive;
    private bool _phoneLostReported;
    private bool _prevRaceOn;
    private DateTime _lastPadErrorUtc = DateTime.MinValue;

    public PhoneServer(IVirtualPad pad, ServerOptions options)
    {
        _pad = pad;
        _options = options;
        _synth = new HapticSynth(options.Haptics);
        _pad.RumbleReceived += OnRumbleReceived;

        _inputSocket = new UdpClient(new IPEndPoint(IPAddress.Any, options.InputPort));
        _inputSocket.Client.ReceiveBufferSize = 1 << 20;

        _telemetrySocket = new UdpClient(new IPEndPoint(IPAddress.Any, options.TelemetryPort));
        _telemetrySocket.Client.ReceiveBufferSize = 1 << 20;

        _feedbackSocket = new UdpClient();
    }

    public IPEndPoint? PhoneEndpoint
    {
        get
        {
            lock (_gate)
            {
                return _phone;
            }
        }
    }

    public async Task RunAsync(CancellationToken ct)
    {
        Console.WriteLine($"  ввод телефона : UDP {_options.ListenAddress}:{_options.InputPort}");
        Console.WriteLine($"  телеметрия FH6: UDP 0.0.0.0:{_options.TelemetryPort}");
        Console.WriteLine($"  обратная связь: UDP <телефон>:{_options.FeedbackPort}");
        Console.WriteLine();

        var input = InputLoopAsync(ct);
        var telemetry = TelemetryLoopAsync(ct);
        var pad = PadLoopAsync(ct);

        await Task.WhenAll(input, telemetry, pad).ConfigureAwait(false);
    }

    // --- ввод с телефона -----------------------------------------------------

    private async Task InputLoopAsync(CancellationToken ct)
    {
        while (!ct.IsCancellationRequested)
        {
            UdpReceiveResult result;
            try
            {
                result = await _inputSocket.ReceiveAsync(ct).ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
                return;
            }
            catch (ObjectDisposedException)
            {
                return;
            }

            if (!Protocol.TryDecodeInput(result.Buffer, out var type, out var state))
            {
                continue;
            }

            lock (_gate)
            {
                _phone = result.RemoteEndPoint;

                switch (type)
                {
                    case InputPacketType.State:
                        // отбрасываем «старые» пакеты (sequence с оборачиванием)
                        if (_haveSequence && !IsNewer(state.Sequence, _lastSequence))
                        {
                            break;
                        }

                        _lastSequence = state.Sequence;
                        _haveSequence = true;
                        _latest = state;
                        _lastInputUtc = DateTime.UtcNow;
                        _phoneLostReported = false;
                        break;

                    case InputPacketType.Hello:
                        // Новое подключение: сбрасываем счётчик пакетов, иначе
                        // пакеты новой сессии будут отброшены как «старые».
                        _haveSequence = false;
                        _lastSequence = 0;
                        _latest = GamepadState.Empty;
                        SendStatus(StatusCodes.PhoneConnected, 0);
                        SendSound(SoundIds.Startup, 0);
                        Console.WriteLine($"  телефон подключился: {result.RemoteEndPoint}");
                        break;

                    case InputPacketType.Goodbye:
                        SendStatus(StatusCodes.PhoneDisconnected, 0);
                        _latest = GamepadState.Empty;
                        _haveSequence = false;
                        _lastInputUtc = DateTime.MinValue;
                        StopFeedback();
                        Console.WriteLine("  телефон отключился");
                        break;

                    case InputPacketType.Ping:
                        // Ответ на пинг: телефон по нему понимает, что сервер жив.
                        SendStatus(StatusCodes.PadReady, 0);
                        break;
                }
            }
        }
    }

    private static bool IsNewer(ushort sequence, ushort last)
    {
        return Protocol.IsNewerSequence(sequence, last);
    }

    // --- отчёты в игру -------------------------------------------------------

    private async Task PadLoopAsync(CancellationToken ct)
    {
        var period = TimeSpan.FromSeconds(1.0 / Math.Max(20, _options.PadRateHz));
        using var timer = new PeriodicTimer(period);

        while (await timer.WaitForNextTickAsync(ct).ConfigureAwait(false))
        {
            GamepadState state;
            bool timedOut;

            lock (_gate)
            {
                timedOut = _lastInputUtc != DateTime.MinValue
                    && (DateTime.UtcNow - _lastInputUtc).TotalMilliseconds > _options.PhoneTimeoutMs;
                state = timedOut ? GamepadState.Empty : _latest;
            }

            if (timedOut)
            {
                // Телефон замолчал — обнуляем пад, иначе газ остался бы выжатым.
                lock (_gate)
                {
                    _latest = GamepadState.Empty;
                    _lastInputUtc = DateTime.MinValue;
                    if (!_phoneLostReported)
                    {
                        _phoneLostReported = true;
                        Console.WriteLine("  связь с телефоном потеряна — ввод сброшен");
                    }
                }
            }

            try
            {
                _pad.Apply(PadInput.FromState(state));
            }
            catch (Exception ex)
            {
                // Не роняем весь сервер из-за одной ошибки отправки отчёта,
                // но и не спамим в лог: пишем не чаще раза в 5 секунд.
                var now = DateTime.UtcNow;
                if ((now - _lastPadErrorUtc).TotalSeconds >= 5)
                {
                    _lastPadErrorUtc = now;
                    Console.WriteLine($"  ошибка виртуального пада: {ex.Message}");
                }
            }
        }
    }

    // --- телеметрия FH6 → тактильные эффекты, звук, HUD -----------------------

    private async Task TelemetryLoopAsync(CancellationToken ct)
    {
        while (!ct.IsCancellationRequested)
        {
            UdpReceiveResult result;
            try
            {
                result = await _telemetrySocket.ReceiveAsync(ct).ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
                return;
            }
            catch (ObjectDisposedException)
            {
                return;
            }

            if (!Fh6Telemetry.TryParse(result.Buffer, out var telemetry) || telemetry is null)
            {
                continue;
            }

            var frame = _synth.Compute(telemetry, DateTime.UtcNow);

            if (!frame.Body.IsSilent)
            {
                SendBody(frame.Body);
                _bodyActive = true;
            }
            else if (_bodyActive)
            {
                // Эффект закончился — говорим телефону прекратить вибрацию.
                SendBody(BodyHaptics.None);
                _bodyActive = false;
            }

            if (!frame.Triggers.IsSilent)
            {
                SendTriggers(frame.Triggers);
                _triggersActive = true;
            }
            else if (_triggersActive)
            {
                SendTriggers(TriggerHaptics.None);
                _triggersActive = false;
            }

            foreach (byte sound in frame.Sounds)
            {
                SendSound(sound, frame.SoundParam);
            }

            // «Световая полоса»: телефон не умеет менять цвет LED, поэтому
            // сервер шлёт цвет, который телефон рисует полосой на экране.
            if (frame.Sounds.Contains(SoundIds.AbsPulse))
            {
                SendLed(255, 40, 40);
            }
            else if (frame.Sounds.Contains(SoundIds.Collision))
            {
                SendLed(255, 255, 255);
            }

            if (telemetry.IsRaceOn && !_prevRaceOn)
            {
                SendLed(255, 140, 0);
            }
            _prevRaceOn = telemetry.IsRaceOn;

            DateTime now = DateTime.UtcNow;
            if ((now - _lastHudUtc).TotalMilliseconds >= 50)
            {
                _lastHudUtc = now;
                SendHud(telemetry);
            }
        }
    }

    // --- обратная связь ------------------------------------------------------

    private void OnRumbleReceived(byte large, byte small)
    {
        lock (_gate)
        {
            if (large == _lastRumbleLarge && small == _lastRumbleSmall)
            {
                return;
            }

            _lastRumbleLarge = large;
            _lastRumbleSmall = small;
        }

        var payload = new byte[4];
        payload[0] = large;
        payload[1] = small;
        BinaryPrimitives.WriteUInt16LittleEndian(payload.AsSpan(2), 0);
        SendFeedback(FeedbackType.Rumble, payload);
    }

    /// <summary>Останавливает все текущие тактильные эффекты (разрыв связи, конец гонки).</summary>
    private void StopFeedback()
    {
        if (_bodyActive)
        {
            SendBody(BodyHaptics.None);
            _bodyActive = false;
        }

        if (_triggersActive)
        {
            SendTriggers(TriggerHaptics.None);
            _triggersActive = false;
        }
    }

    private void SendBody(BodyHaptics body)
    {
        SendFeedback(FeedbackType.Body, FeedbackCodec.EncodeBody(body));
    }

    private void SendTriggers(TriggerHaptics triggers)
    {
        SendFeedback(FeedbackType.Trigger, FeedbackCodec.EncodeTriggers(triggers));
    }

    private void SendSound(byte soundId, byte param)
    {
        SendFeedback(FeedbackType.Sound, FeedbackCodec.EncodeSound(soundId, param));
    }

    private void SendLed(byte r, byte g, byte b)
    {
        SendFeedback(FeedbackType.Led, FeedbackCodec.EncodeLed(r, g, b));
    }

    private void SendHud(Fh6Telemetry t)
    {
        SendFeedback(FeedbackType.Hud, FeedbackCodec.EncodeHud(t));
    }

    private void SendStatus(byte code, byte detail)
    {
        SendFeedback(FeedbackType.Status, FeedbackCodec.EncodeStatus(code, detail));
    }

    private void SendFeedback(FeedbackType type, byte[] payload)
    {
        IPEndPoint? endpoint;
        lock (_gate)
        {
            endpoint = _phone;
        }

        if (endpoint is null)
        {
            return;
        }

        var packet = Protocol.EncodeFeedback(type, payload);
        try
        {
            // Важно: вторым аргументом идёт длина всего датаграммы, а не полезной нагрузки.
            _feedbackSocket.Send(packet, packet.Length, new IPEndPoint(endpoint.Address, _options.FeedbackPort));
        }
        catch (SocketException ex)
        {
            if (_options.Verbose)
            {
                Console.WriteLine($"  не удалось отправить обратную связь: {ex.Message}");
            }
        }
        catch (ObjectDisposedException)
        {
            // сервер уже останавливается — тихо выходим
        }
    }

    public async ValueTask DisposeAsync()
    {
        _pad.RumbleReceived -= OnRumbleReceived;
        _inputSocket.Dispose();
        _telemetrySocket.Dispose();
        _feedbackSocket.Dispose();
        await Task.CompletedTask;
    }
}

public static class StatusCodes
{
    public const byte PhoneConnected = 1;
    public const byte PhoneDisconnected = 2;
    public const byte PadReady = 3;
}
