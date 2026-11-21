namespace PhonePad.Core;

/// <summary>Две полосы тактильной обратной связи: «низкая» (вес/удары) и «высокая» (текстура).</summary>
public readonly record struct BodyHaptics(
    byte LowStrength,
    byte LowFrequency,
    byte HighStrength,
    byte HighFrequency,
    ushort DurationMs)
{
    public static BodyHaptics None => new(0, 0, 0, 0, 0);

    public bool IsSilent => LowStrength == 0 && HighStrength == 0;
}

/// <summary>Эффект «адаптивного» триггера: сопротивление/пульсация вместо реального сопротивления.</summary>
public readonly record struct TriggerHaptics(byte Left, byte Right, ushort DurationMs)
{
    public static TriggerHaptics None => new(0, 0, 0);

    public bool IsSilent => Left == 0 && Right == 0;
}

/// <summary>Кадр эффектов, вычисленный из телеметрии FH6.</summary>
public sealed class HapticFrame
{
    public BodyHaptics Body { get; set; } = BodyHaptics.None;
    public TriggerHaptics Triggers { get; set; } = TriggerHaptics.None;
    public List<byte> Sounds { get; } = new();
    public byte SoundParam { get; set; }
}

/// <summary>
/// Синтез «DualSense-ощущений» из телеметрии Forza Horizon 6.
/// Логика повторяет подход HorizonHaptics/ForzaHaptics, но результат уходит в телефон:
/// две полосы вибрации (низкая/высокая), эффекты триггеров и звуки.
/// </summary>
public sealed class HapticSynth
{
    private readonly HapticOptions _options;

    private int _prevGear;
    private bool _prevRumbleStrip;
    private byte _prevBrake;
    private float _prevAccelX;
    private float _prevAccelZ;
    private readonly float[] _prevSuspension = new float[4];
    private DateTime _prevFrameUtc = DateTime.MinValue;
    private bool _initialized;

    public HapticSynth(HapticOptions? options = null)
    {
        _options = options ?? new HapticOptions();
    }

    /// <summary>Вычисляет кадр эффектов. Вызывать каждый раз при получении пакета телеметрии.</summary>
    public HapticFrame Compute(Fh6Telemetry telemetry, DateTime nowUtc)
    {
        var frame = new HapticFrame();

        if (!telemetry.IsRaceOn)
        {
            _initialized = false;
            _prevFrameUtc = DateTime.MinValue;
            return frame;
        }

        if (!_initialized)
        {
            _prevGear = telemetry.Gear;
            _prevAccelX = telemetry.AccelerationX;
            _prevAccelZ = telemetry.AccelerationZ;
            _prevBrake = telemetry.Brake;
            Array.Copy(telemetry.SuspensionTravel, _prevSuspension, 4);
            _prevRumbleStrip = telemetry.AnyRumbleStrip;
            _prevFrameUtc = nowUtc;
            _initialized = true;
            return frame;
        }

        // Время между кадрами нужно, чтобы «рывок» и «стук подвески» не зависели
        // от частоты телеметрии: при 30 Гц те же события давали бы вдвое меньший
        // отклик, чем при 60 Гц.
        float dt = _prevFrameUtc == DateTime.MinValue
            ? 1f / 60f
            : (float)(nowUtc - _prevFrameUtc).TotalSeconds;
        dt = Math.Clamp(dt, 0.005f, 0.5f);

        // --- низкая полоса ------------------------------------------------
        byte lowStrength = 0;
        byte lowFrequency = 40;

        // Двигатель: ровный низкий гул, растёт с оборотами.
        if (_options.EngineFeedback && telemetry.EngineMaxRpm > 0f)
        {
            float rpmRatio = Math.Clamp(telemetry.EngineRpm / telemetry.EngineMaxRpm, 0f, 1f);
            lowStrength = (byte)Math.Clamp(lowStrength + rpmRatio * 55f * _options.EngineLevel, 0, 255);
            lowFrequency = (byte)Math.Clamp(35 + rpmRatio * 60f, 0, 255);
        }

        // Удар: рывок ускорения (jerk), приведённый к единице времени.
        float jerkX = Math.Abs(telemetry.AccelerationX - _prevAccelX) / dt;
        float jerkZ = Math.Abs(telemetry.AccelerationZ - _prevAccelZ) / dt;
        float jerk = MathF.Sqrt(jerkX * jerkX + jerkZ * jerkZ);
        if (jerk > 40f)
        {
            float intensity = Math.Clamp((jerk - 40f) / 260f, 0f, 1f) * (float)_options.CollisionLevel;
            lowStrength = (byte)Math.Clamp(lowStrength + intensity * 230f, 0, 255);
            lowFrequency = (byte)Math.Clamp(70 + intensity * 60f, 0, 255);
            frame.Sounds.Add(SoundIds.Collision);
            frame.SoundParam = (byte)Math.Clamp(intensity * 255f, 0, 255);
        }

        // Стук подвески (яма, кочка, прыжок): скорость сжатия подвески.
        float thud = 0f;
        for (int i = 0; i < 4; i++)
        {
            float rate = (telemetry.SuspensionTravel[i] - _prevSuspension[i]) / dt;
            if (rate < -0.6f)
            {
                thud = Math.Max(thud, Math.Min(1f, -rate / 2.5f));
            }
        }

        if (thud > 0f)
        {
            lowStrength = (byte)Math.Clamp(lowStrength + thud * 170f, 0, 255);
            lowFrequency = 55;
        }

        // Rumble strip: резкая низкочастотная тряска.
        if (telemetry.AnyRumbleStrip)
        {
            lowStrength = (byte)Math.Clamp(lowStrength + 210f * _options.SurfaceLevel, 0, 255);
            lowFrequency = 65;
        }

        // --- высокая полоса (текстура поверхности, пробуксовка) ------------
        byte highStrength = 0;
        byte highFrequency = 60;

        float surface = Math.Clamp(telemetry.SurfaceRumbleAverage, 0f, 1f);
        if (surface > 0f)
        {
            highStrength = (byte)Math.Clamp(surface * 200f * _options.SurfaceLevel, 0, 255);
            highFrequency = (byte)Math.Clamp(45 + surface * 120f, 0, 255);
        }

        // Пробуксовка: газ + скольжение задних колёс.
        if (telemetry.Throttle > 40 && telemetry.RearSlip > 1f)
        {
            float spin = Math.Clamp((telemetry.RearSlip - 1f) / 3f, 0f, 1f);
            highStrength = (byte)Math.Clamp(highStrength + spin * (telemetry.Throttle / 255f) * 220f, 0, 255);
            highFrequency = (byte)Math.Clamp(90 + spin * 80f, 0, 255);
        }

        // --- триггеры ------------------------------------------------------
        byte lt = 0;
        byte rt = 0;

        // «Сопротивление» под нагрузкой: педаль давит — триггер ощущает нагрузку.
        if (_options.TriggerResistance)
        {
            lt = (byte)Math.Clamp(telemetry.Brake / 255f * 200f, 0, 255);
            rt = (byte)Math.Clamp(telemetry.Throttle / 255f * 170f, 0, 255);
        }

        // ABS: пульсация левого триггера при потере сцепления под тормозом.
        if (telemetry.Brake > 40 && telemetry.FrontSlip > 1f)
        {
            float absAmount = Math.Clamp((telemetry.FrontSlip - 1f) / 2f, 0f, 1f);
            lt = (byte)Math.Clamp(Math.Max(lt, 90f + absAmount * 150f), 0, 255);
            if (Math.Abs(telemetry.Brake - _prevBrake) > 12)
            {
                frame.Sounds.Add(SoundIds.AbsPulse);
                frame.SoundParam = (byte)Math.Clamp(absAmount * 255f, 0, 255);
            }
        }

        // Ручник: резкое сопротивление левого триггера.
        if (telemetry.HandBrake != 0)
        {
            lt = (byte)Math.Clamp(Math.Max(lt, 220f), 0, 255);
        }

        // --- события --------------------------------------------------------
        if (telemetry.Gear != _prevGear && telemetry.Gear != 0)
        {
            frame.Sounds.Add(SoundIds.GearShift);
            lowStrength = (byte)Math.Clamp(lowStrength + 110f, 0, 255);
            highStrength = (byte)Math.Clamp(highStrength + 90f, 0, 255);
        }

        if (telemetry.AnyRumbleStrip != _prevRumbleStrip)
        {
            frame.Sounds.Add(SoundIds.SurfaceChange);
        }

        frame.Body = new BodyHaptics(
            lowStrength,
            lowFrequency,
            highStrength,
            highFrequency,
            (ushort)Math.Clamp(_options.DurationMs, 0, ushort.MaxValue));
        frame.Triggers = new TriggerHaptics(lt, rt, (ushort)Math.Clamp(_options.DurationMs, 0, ushort.MaxValue));

        // Сохраняем состояние для следующего кадра.
        _prevGear = telemetry.Gear;
        _prevAccelX = telemetry.AccelerationX;
        _prevAccelZ = telemetry.AccelerationZ;
        Array.Copy(telemetry.SuspensionTravel, _prevSuspension, 4);
        _prevRumbleStrip = telemetry.AnyRumbleStrip;
        _prevBrake = telemetry.Brake;
        _prevFrameUtc = nowUtc;

        return frame;
    }
}

/// <summary>Настройки интенсивности (можно крутить в конфиге).</summary>
public sealed class HapticOptions
{
    /// <summary>Гул двигателя в низкой полосе.</summary>
    public bool EngineFeedback { get; set; } = true;

    public double EngineLevel { get; set; } = 1.0;

    public double CollisionLevel { get; set; } = 1.0;

    public double SurfaceLevel { get; set; } = 1.0;

    /// <summary>Имитация сопротивления триггеров.</summary>
    public bool TriggerResistance { get; set; } = true;

    public int DurationMs { get; set; } = 60;
}
