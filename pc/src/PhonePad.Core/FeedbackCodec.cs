using System.Buffers.Binary;

namespace PhonePad.Core;

/// <summary>
/// Кодирование сообщений обратной связи («ПК → телефон»).
/// Вынесено в Core, чтобы формат пакетов проверялся самопроверкой.
/// </summary>
public static class FeedbackCodec
{
    /// <summary>Размер полезной нагрузки HUD (11 байт — базовый, 13 — с maxRpm).</summary>
    public const int HudPayloadSize = 13;

    public static byte[] EncodeHud(Fh6Telemetry t)
    {
        var payload = new byte[HudPayloadSize];
        BinaryPrimitives.WriteUInt16LittleEndian(payload.AsSpan(0), (ushort)Math.Clamp(t.SpeedKmh, 0, 65535));
        payload[2] = t.Gear;
        BinaryPrimitives.WriteUInt16LittleEndian(payload.AsSpan(3), (ushort)Math.Clamp(t.EngineRpm, 0, 65535));
        BinaryPrimitives.WriteInt16LittleEndian(payload.AsSpan(5),
            (short)Math.Clamp(t.AccelerationX * 100f, short.MinValue, short.MaxValue));
        payload[7] = t.Throttle;
        payload[8] = t.Brake;
        payload[9] = (byte)Math.Clamp(t.FourWheelSlip * 40f, 0, 255);
        payload[10] = (byte)((t.IsRaceOn ? 1 : 0) | (t.AnyRumbleStrip ? 2 : 0));
        BinaryPrimitives.WriteUInt16LittleEndian(payload.AsSpan(11), (ushort)Math.Clamp(t.MaxRpmForHud, 0, 65535));
        return payload;
    }

    public static byte[] EncodeBody(BodyHaptics body)
    {
        var payload = new byte[6];
        payload[0] = body.LowStrength;
        payload[1] = body.LowFrequency;
        payload[2] = body.HighStrength;
        payload[3] = body.HighFrequency;
        BinaryPrimitives.WriteUInt16LittleEndian(payload.AsSpan(4), body.DurationMs);
        return payload;
    }

    public static byte[] EncodeTriggers(TriggerHaptics triggers)
    {
        var payload = new byte[4];
        payload[0] = triggers.Left;
        payload[1] = triggers.Right;
        BinaryPrimitives.WriteUInt16LittleEndian(payload.AsSpan(2), triggers.DurationMs);
        return payload;
    }

    public static byte[] EncodeLed(byte r, byte g, byte b) => new[] { r, g, b };

    public static byte[] EncodeSound(byte soundId, byte param) => new[] { soundId, param };

    public static byte[] EncodeStatus(byte code, byte detail) => new[] { code, detail };
}
