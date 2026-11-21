using System.Buffers.Binary;

namespace PhonePad.Core;

/// <summary>
/// Разобранный кадр телеметрии Forza Horizon 6 (Data Out).
/// Эталонный размер пакета — 324 байта; разбор устойчив к более коротким
/// вариантам (232 байта в некоторых режимах Data Out): недостающие поля
/// считаются нулевыми, а не ломают весь кадр.
/// Смещения — по официальной спецификации FH6 Data Out.
/// </summary>
public sealed class Fh6Telemetry
{
    /// <summary>Эталонный размер пакета телеметрии FH6.</summary>
    public const int PacketSize = 324;

    /// <summary>Минимальный размер, начиная с которого пакет считается телеметрией.</summary>
    public const int MinPacketSize = 64;

    public bool IsRaceOn;
    public float EngineMaxRpm;
    public float EngineIdleRpm;
    public float EngineRpm;
    public float AccelerationX;
    public float AccelerationZ;

    public float[] SuspensionTravel = new float[4]; // FL, FR, RL, RR
    public bool[] OnRumbleStrip = new bool[4];
    public float[] PuddleDepth = new float[4];
    public float[] SurfaceRumble = new float[4];
    public float[] WheelSlip = new float[4];

    public float CollisionVelocityDelta;
    public float Speed;                 // м/с
    public float Boost;
    public byte Throttle;               // 0..255
    public byte Brake;                  // 0..255
    public byte HandBrake;
    public byte Gear;
    public sbyte Steer;                 // −127..127

    public double SpeedKmh => Speed * 3.6;
    public float FourWheelSlip => (Math.Abs(WheelSlip[0]) + Math.Abs(WheelSlip[1]) + Math.Abs(WheelSlip[2]) + Math.Abs(WheelSlip[3])) / 4f;
    public float FrontSlip => (Math.Abs(WheelSlip[0]) + Math.Abs(WheelSlip[1])) / 2f;
    public float RearSlip => (Math.Abs(WheelSlip[2]) + Math.Abs(WheelSlip[3])) / 2f;
    public float SurfaceRumbleAverage => (SurfaceRumble[0] + SurfaceRumble[1] + SurfaceRumble[2] + SurfaceRumble[3]) / 4f;
    public bool AnyRumbleStrip => OnRumbleStrip[0] || OnRumbleStrip[1] || OnRumbleStrip[2] || OnRumbleStrip[3];

    /// <summary>Максимальное число оборотов двигателя (красная зона) — для шкалы оборотов в HUD.</summary>
    public int MaxRpmForHud => EngineMaxRpm > 1f ? (int)Math.Round(EngineMaxRpm) : 7500;

    /// <summary>Разбирает пакет. Возвращает false, если это явно не телеметрия.</summary>
    public static bool TryParse(ReadOnlySpan<byte> data, out Fh6Telemetry? telemetry)
    {
        telemetry = null;
        if (data.Length < MinPacketSize)
        {
            return false;
        }

        var t = new Fh6Telemetry
        {
            IsRaceOn = ReadFloat(data, 0) > 0f,
            EngineMaxRpm = ReadFloat(data, 8),
            EngineIdleRpm = ReadFloat(data, 12),
            EngineRpm = ReadFloat(data, 16),
            AccelerationX = ReadFloat(data, 20),
            AccelerationZ = ReadFloat(data, 28),
            CollisionVelocityDelta = ReadFloat(data, 236),
            Speed = ReadFloat(data, 256),
            Boost = ReadFloat(data, 284),
            Throttle = ReadByte(data, 315),
            Brake = ReadByte(data, 316),
            HandBrake = ReadByte(data, 318),
            Gear = ReadByte(data, 319),
            Steer = (sbyte)ReadByte(data, 320)
        };

        for (int i = 0; i < 4; i++)
        {
            t.SuspensionTravel[i] = ReadFloat(data, 68 + i * 4);
            t.OnRumbleStrip[i] = ReadInt(data, 116 + i * 4) != 0;
            t.PuddleDepth[i] = ReadFloat(data, 132 + i * 4);
            t.SurfaceRumble[i] = ReadFloat(data, 148 + i * 4);
            t.WheelSlip[i] = ReadFloat(data, 180 + i * 4);
        }

        telemetry = t;
        return true;
    }

    private static float ReadFloat(ReadOnlySpan<byte> data, int offset)
    {
        if (offset + 4 > data.Length)
        {
            return 0f;
        }

        return BitConverter.ToSingle(data.Slice(offset, 4));
    }

    private static int ReadInt(ReadOnlySpan<byte> data, int offset)
    {
        if (offset + 4 > data.Length)
        {
            return 0;
        }

        return BinaryPrimitives.ReadInt32LittleEndian(data[offset..]);
    }

    private static byte ReadByte(ReadOnlySpan<byte> data, int offset)
    {
        return offset < data.Length ? data[offset] : (byte)0;
    }
}
