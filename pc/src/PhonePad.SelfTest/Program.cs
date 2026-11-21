using System.Buffers.Binary;
using PhonePad.Core;

namespace PhonePad.SelfTest;

/// <summary>
/// Проверка протокола, разбора телеметрии FH6 и синтеза тактильных эффектов.
/// Запуск: dotnet run --project pc/src/PhonePad.SelfTest
/// </summary>
public static class Program
{
    private static int _failed;

    public static int Main()
    {
        Console.WriteLine("=== PhonePad SelfTest ===");
        Console.WriteLine();

        TestProtocolRoundTrip();
        TestCrcDetectsCorruption();
        TestUnknownPacketTypeRejected();
        TestFeedbackRoundTrip();
        TestSequenceOrdering();
        TestTelemetryParsing();
        TestTelemetryShortPacket();
        TestHapticSynthesis();
        TestCollisionDetection();
        TestHudEncoding();
        TestButtonMapping();

        Console.WriteLine();
        if (_failed == 0)
        {
            Console.WriteLine("ВСЕ ПРОВЕРКИ ПРОЙДЕНЫ");
            return 0;
        }

        Console.WriteLine($"ПРОВАЛЕНО проверок: {_failed}");
        return 1;
    }

    private static void Check(bool condition, string name, string detail = "")
    {
        if (condition)
        {
            Console.WriteLine($"  [OK]   {name}");
        }
        else
        {
            _failed++;
            Console.WriteLine($"  [FAIL] {name} {detail}");
        }
    }

    private static void TestProtocolRoundTrip()
    {
        Console.WriteLine("Протокол: round-trip");
        var state = new GamepadState
        {
            Buttons = PadButtons.A | PadButtons.LeftShoulder | PadButtons.DPadRight,
            LeftTrigger = 128,
            RightTrigger = 200,
            LeftX = -1000,
            LeftY = 500,
            RightX = 123,
            RightY = -456,
            GyroPitch = 1500,
            GyroRoll = -2500,
            Sequence = 4242
        };

        byte[] packet = Protocol.EncodeState(state, gyroActive: true);
        Check(packet.Length == Protocol.InputPacketSize, "размер пакета = 23 байта", $"получено {packet.Length}");

        bool ok = Protocol.TryDecodeInput(packet, out var type, out var decoded);
        Check(ok, "пакет декодируется");
        Check(type == InputPacketType.State, "тип = State");
        Check(decoded.Buttons == state.Buttons, "маска кнопок сохранена");
        Check(decoded.LeftTrigger == 128 && decoded.RightTrigger == 200, "триггеры сохранены");
        Check(decoded.LeftX == -1000 && decoded.LeftY == 500, "левая ось сохранена");
        Check(decoded.RightX == 123 && decoded.RightY == -456, "правая ось сохранена");
        Check(decoded.GyroPitch == 1500 && decoded.GyroRoll == -2500, "гироскоп сохранён");
        Check(decoded.Sequence == 4242, "sequence сохранён");
        Check(packet[3] == 1, "флаг гироскопа выставлен");
    }

    private static void TestCrcDetectsCorruption()
    {
        Console.WriteLine("Протокол: контрольная сумма");
        byte[] packet = Protocol.EncodeState(new GamepadState { Buttons = PadButtons.B });
        packet[10] ^= 0xFF; // портим пакет
        bool ok = Protocol.TryDecodeInput(packet, out _, out _);
        Check(!ok, "испорченный пакет отклоняется");
    }

    private static void TestUnknownPacketTypeRejected()
    {
        Console.WriteLine("Протокол: неизвестный тип пакета");
        byte[] packet = Protocol.EncodeState(new GamepadState());
        packet[2] = 99;
        packet[22] = Protocol.Crc8(packet.AsSpan(0, 22));
        bool ok = Protocol.TryDecodeInput(packet, out _, out _);
        Check(!ok, "пакет с неизвестным типом отклоняется");
    }

    private static void TestFeedbackRoundTrip()
    {
        Console.WriteLine("Протокол: обратная связь");
        var payload = new byte[] { 10, 20, 30, 40 };
        byte[] packet = Protocol.EncodeFeedback(FeedbackType.Body, payload);
        bool ok = Protocol.TryDecodeFeedback(packet, out var type, out var decoded);
        Check(ok, "сообщение декодируется");
        Check(type == FeedbackType.Body, "тип = Body");
        Check(decoded.Length == 4 && decoded[3] == 40, "полезная нагрузка сохранена");

        // Длина полезной нагрузки объявлена в заголовке — лишние байты не должны
        // попасть в разбор.
        byte[] withTail = packet.Concat(new byte[] { 0xAA, 0xBB }).ToArray();
        bool okTail = Protocol.TryDecodeFeedback(withTail, out _, out var decodedTail);
        Check(okTail && decodedTail.Length == 4, "лишние байты за пределами payload отбрасываются",
            $"получено {decodedTail.Length}");
    }

    private static void TestSequenceOrdering()
    {
        Console.WriteLine("Протокол: порядок счётчика пакетов");
        Check(Protocol.IsNewerSequence(11, 10), "11 новее 10");
        Check(!Protocol.IsNewerSequence(10, 10), "повтор не считается новым");
        Check(!Protocol.IsNewerSequence(9, 10), "старый пакет отбрасывается");
        Check(Protocol.IsNewerSequence(0, 65535), "переход через переполнение 65535 → 0");
        Check(!Protocol.IsNewerSequence(65535, 0), "обратный переход через переполнение отбрасывается");
    }

    private static void TestTelemetryParsing()
    {
        Console.WriteLine("Телеметрия FH6: разбор пакета 324 байта");
        var packet = BuildTelemetryPacket(
            isRaceOn: 1f,
            rpm: 6500f,
            maxRpm: 7500f,
            speed: 55.5f,
            throttle: 200,
            brake: 30,
            gear: 4,
            slip: 1.8f,
            surfaceRumble: 0.42f,
            accelX: 3.5f,
            rumbleStrip: true);

        bool ok = Fh6Telemetry.TryParse(packet, out var t);
        Check(ok, "пакет разобран");
        Check(t is not null, "телеметрия получена");
        if (t is null)
        {
            return;
        }

        Check(t.IsRaceOn, "гонка идёт");
        Check(Math.Abs(t.EngineRpm - 6500f) < 0.01f, "обороты", $"получено {t.EngineRpm}");
        Check(Math.Abs(t.SpeedKmh - 199.8f) < 0.5f, "скорость в км/ч", $"получено {t.SpeedKmh:F1}");
        Check(t.Throttle == 200 && t.Brake == 30, "газ/тормоз");
        Check(t.Gear == 4, "передача");
        Check(Math.Abs(t.FourWheelSlip - 1.8f) < 0.01f, "slip", $"получено {t.FourWheelSlip}");
        Check(Math.Abs(t.SurfaceRumbleAverage - 0.42f) < 0.01f, "вибрация поверхности");
        Check(t.AnyRumbleStrip, "колесо на rumble strip");
        Check(Math.Abs(t.AccelerationX - 3.5f) < 0.01f, "боковое ускорение");
        Check(t.MaxRpmForHud == 7500, "макс. обороты для HUD", $"получено {t.MaxRpmForHud}");
    }

    private static void TestTelemetryShortPacket()
    {
        Console.WriteLine("Телеметрия FH6: короткий и мусорный пакет");
        bool shortOk = Fh6Telemetry.TryParse(new byte[100], out var shortTelemetry);
        Check(shortOk, "укороченный пакет разбирается");
        Check(shortTelemetry is not null && shortTelemetry!.Gear == 0, "недоступные поля читаются как ноль");

        bool garbage = Fh6Telemetry.TryParse(new byte[10], out _);
        Check(!garbage, "мусорный пакет отклоняется");
    }

    private static void TestHapticSynthesis()
    {
        Console.WriteLine("Синтез эффектов: телеметрия → вибрация/звук");

        var synth = new HapticSynth();
        var t = Parse(BuildTelemetryPacket(1f, 6500f, 7500f, 55.5f, 200, 30, 4, 1.8f, 0.42f, 3.5f, true));

        // Первый кадр — инициализация состояния, эффектов быть не должно.
        var first = synth.Compute(t, DateTime.UtcNow);
        Check(first.Body.IsSilent && first.Triggers.IsSilent, "первый кадр пустой (инициализация)");

        // Второй кадр с теми же данными: появляется поверхностная вибрация и сопротивление триггера.
        var second = synth.Compute(t, DateTime.UtcNow.AddMilliseconds(16));
        Check(!second.Body.IsSilent, "кузовная вибрация сгенерирована");
        Check(!second.Triggers.IsSilent, "эффект триггера сгенерирован");
        Check(second.Triggers.Left > 0, "сопротивление левого триггера (тормоз) > 0");

        // Смена передачи даёт звук.
        t.Gear = 5;
        var shift = synth.Compute(t, DateTime.UtcNow.AddMilliseconds(32));
        Check(shift.Sounds.Contains(SoundIds.GearShift), "звук переключения передачи");

        // Сильная пробуксовка даёт высокочастотную полосу.
        var spin = Parse(BuildTelemetryPacket(1f, 7000f, 7500f, 40f, 255, 0, 3, 3.5f, 0.9f, 0f, false));
        var spinFrame = synth.Compute(spin, DateTime.UtcNow.AddMilliseconds(48));
        Check(spinFrame.Body.HighStrength > 0, "высокая полоса активна при пробуксовке");
    }

    private static void TestCollisionDetection()
    {
        Console.WriteLine("Синтез эффектов: столкновение (рывок ускорения)");
        var synth = new HapticSynth();

        var calm = Parse(BuildTelemetryPacket(1f, 3000f, 7500f, 30f, 0, 0, 3, 0f, 0f, 0f, false));
        synth.Compute(calm, DateTime.UtcNow);

        // Резкий рывок бокового ускорения: +25 м/с² за 16 мс.
        var hit = Parse(BuildTelemetryPacket(1f, 3000f, 7500f, 30f, 0, 0, 3, 0f, 0f, 25f, false));
        var frame = synth.Compute(hit, DateTime.UtcNow.AddMilliseconds(16));

        Check(frame.Sounds.Contains(SoundIds.Collision), "звук удара при резком ускорении");
        Check(frame.Body.LowStrength > 100, "сильный низкочастотный отклик", $"получено {frame.Body.LowStrength}");

        // Тот же удар, но за 100 мс: приведённый к времени jerk заметно меньше —
        // значит расчёт не зависит от частоты кадров.
        var synth2 = new HapticSynth();
        synth2.Compute(calm, DateTime.UtcNow);
        var slowFrame = synth2.Compute(hit, DateTime.UtcNow.AddMilliseconds(100));
        Check(slowFrame.Body.LowStrength < frame.Body.LowStrength,
            "отклик нормирован по времени между кадрами",
            $"{slowFrame.Body.LowStrength} против {frame.Body.LowStrength}");
    }

    private static void TestHudEncoding()
    {
        Console.WriteLine("Обратная связь: кодирование HUD");
        var t = Parse(BuildTelemetryPacket(1f, 6500f, 7500f, 55.5f, 200, 30, 4, 1.8f, 0.42f, 3.5f, true));
        byte[] payload = FeedbackCodec.EncodeHud(t);

        Check(payload.Length == FeedbackCodec.HudPayloadSize, "размер HUD = 13 байт", $"получено {payload.Length}");

        int speed = payload[0] | (payload[1] << 8);
        int gear = payload[2];
        int rpm = payload[3] | (payload[4] << 8);
        int maxRpm = payload[11] | (payload[12] << 8);
        int flags = payload[10];

        Check(Math.Abs(speed - 199.8f) < 2, "скорость в HUD", $"получено {speed}");
        Check(gear == 4, "передача в HUD");
        Check(rpm == 6500, "обороты в HUD", $"получено {rpm}");
        Check(maxRpm == 7500, "макс. обороты в HUD", $"получено {maxRpm}");
        Check((flags & 1) != 0, "флаг «гонка идёт»");
        Check((flags & 2) != 0, "флаг «rumble strip»");

        byte[] led = FeedbackCodec.EncodeLed(255, 40, 40);
        Check(led.Length == 3 && led[0] == 255 && led[2] == 40, "LED кодируется как RGB");
    }

    private static void TestButtonMapping()
    {
        Console.WriteLine("Маппинг кнопок: PadButtons → XUSB");
        ushort mask = XusbButtons.FromPadButtons(PadButtons.A | PadButtons.Start | PadButtons.LeftShoulder);
        Check((mask & XusbButtons.A) != 0, "A → 0x0800");
        Check((mask & XusbButtons.Start) != 0, "Start → 0x0010");
        Check((mask & XusbButtons.LeftShoulder) != 0, "LB → 0x0100");
        Check(mask == 0x0910, "итоговая маска верна", $"получено 0x{mask:X4}");
    }

    private static Fh6Telemetry Parse(byte[] packet)
    {
        Fh6Telemetry.TryParse(packet, out var t);
        return t ?? throw new InvalidOperationException("не удалось разобрать пакет");
    }

    /// <summary>Собирает синтетический пакет телеметрии FH6 с заданными значениями.</summary>
    private static byte[] BuildTelemetryPacket(
        float isRaceOn,
        float rpm,
        float maxRpm,
        float speed,
        byte throttle,
        byte brake,
        byte gear,
        float slip,
        float surfaceRumble,
        float accelX,
        bool rumbleStrip)
    {
        var data = new byte[Fh6Telemetry.PacketSize];

        void PutF(int offset, float value) => BitConverter.TryWriteBytes(data.AsSpan(offset, 4), value);
        void PutI(int offset, int value) => BinaryPrimitives.WriteInt32LittleEndian(data.AsSpan(offset, 4), value);

        PutF(0, isRaceOn);
        PutF(8, maxRpm);
        PutF(12, 900f);
        PutF(16, rpm);
        PutF(20, accelX);
        PutF(28, 2.5f);

        for (int i = 0; i < 4; i++)
        {
            PutF(68 + i * 4, -0.01f * (i + 1));
            PutI(116 + i * 4, rumbleStrip && i < 2 ? 1 : 0);
            PutF(132 + i * 4, 0f);
            PutF(148 + i * 4, surfaceRumble);
            PutF(180 + i * 4, slip);
        }

        PutF(236, 0f);
        PutF(256, speed);
        PutF(284, 0.4f);
        data[315] = throttle;
        data[316] = brake;
        data[318] = 0;
        data[319] = gear;
        data[320] = 0;

        return data;
    }
}
