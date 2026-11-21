#!/usr/bin/env python3
"""
Симулятор телефона для PhonePad — позволяет отлаживать PC-сервер без iOS-устройства.

Режимы:
  state     — шлёт пакеты ввода (100 Гц) и печатает входящую обратную связь
  telemetry — шлёт синтетическую телеметрию FH6 (324 байта) на порт 5300,
              чтобы проверить конвейер «телеметрия → вибрация/звук» без запуска игры
  both      — одновременно ввод и телеметрия
  selftest  — проверяет кодирование/декодирование протокола локально (сеть не нужна)

Примеры:
  python3 phone_sim.py --host 127.0.0.1 --mode state --duration 5
  python3 phone_sim.py --host 127.0.0.1 --mode telemetry --duration 5
  python3 phone_sim.py --host 127.0.0.1 --mode both --duration 10
  python3 phone_sim.py --mode selftest
"""

import argparse
import math
import socket
import struct
import sys
import time

# Чтобы русский текст не превращался в «кракозябры» в консоли Windows.
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

INPUT_MAGIC = 0xF1
FEEDBACK_MAGIC = 0xF2
VERSION = 1
INPUT_PACKET_SIZE = 23
TELEMETRY_PACKET_SIZE = 324

# маска кнопок (см. docs/PROTOCOL.md)
BTN = {
    "dpad_up": 1 << 0,
    "dpad_down": 1 << 1,
    "dpad_left": 1 << 2,
    "dpad_right": 1 << 3,
    "lb": 1 << 4,
    "rb": 1 << 5,
    "back": 1 << 6,
    "start": 1 << 7,
    "l3": 1 << 8,
    "r3": 1 << 9,
    "guide": 1 << 10,
    "mute": 1 << 11,
    "a": 1 << 12,
    "b": 1 << 13,
    "x": 1 << 14,
    "y": 1 << 15,
}


def crc8(data: bytes) -> int:
    crc = 0
    for b in data:
        crc ^= b
        for _ in range(8):
            crc = ((crc << 1) ^ 0x07) & 0xFF if crc & 0x80 else (crc << 1) & 0xFF
    return crc


def encode_state(buttons=0, lt=0, rt=0, lx=0, ly=0, rx=0, ry=0,
                 gyro_pitch=0, gyro_roll=0, seq=0, gyro_active=False) -> bytes:
    body = struct.pack(
        "<BBBBHBBhhhhhhH",
        INPUT_MAGIC, VERSION, 1, 1 if gyro_active else 0,
        buttons & 0xFFFF,
        lt, rt,
        lx, ly, rx, ry,
        gyro_pitch, gyro_roll,
        seq,
    )
    return body + bytes([crc8(body)])


def encode_control(ptype: int) -> bytes:
    body = struct.pack("<BBBB", INPUT_MAGIC, VERSION, ptype, 0) + b"\x00" * 18
    return body + bytes([crc8(body)])


def build_telemetry(is_race=1.0, rpm=6500.0, max_rpm=7500.0, speed=55.0,
                    throttle=200, brake=30, gear=4, slip=1.5,
                    surface=0.4, accel_x=3.0, rumble_strip=False) -> bytes:
    data = bytearray(TELEMETRY_PACKET_SIZE)

    def put_f(off, value):
        struct.pack_into("<f", data, off, value)

    def put_i(off, value):
        struct.pack_into("<i", data, off, value)

    put_f(0, is_race)
    put_f(8, max_rpm)
    put_f(12, 900.0)
    put_f(16, rpm)
    put_f(20, accel_x)
    put_f(28, 2.0)

    for i in range(4):
        put_f(68 + i * 4, -0.01 * (i + 1))
        put_i(116 + i * 4, 1 if (rumble_strip and i < 2) else 0)
        put_f(132 + i * 4, 0.0)
        put_f(148 + i * 4, surface)
        put_f(180 + i * 4, slip)

    put_f(236, 0.0)
    put_f(256, speed)
    put_f(284, 0.3)
    data[315] = throttle & 0xFF
    data[316] = brake & 0xFF
    data[318] = 0
    data[319] = gear & 0xFF
    struct.pack_into("<b", data, 320, 0)
    return bytes(data)


def decode_feedback(data: bytes):
    """Разбирает сообщение обратной связи. Возвращает (тип, полезная нагрузка)."""
    if len(data) < 4 or data[0] != FEEDBACK_MAGIC or data[1] != VERSION:
        return None, b""
    length = data[3]
    payload = data[4:4 + length]
    return data[2], payload


def describe_feedback(data: bytes) -> str:
    ftype, payload = decode_feedback(data)
    if ftype is None:
        return f"?? {data!r}"
    if ftype == 1:
        large, small, dur = struct.unpack("<BBH", payload[:4])
        return f"Rumble  моторы={large}/{small} мс={dur}"
    if ftype == 2:
        ls, lf, hs, hf, dur = struct.unpack("<BBBBH", payload[:6])
        return f"Body    низ={ls}@{lf}Гц верх={hs}@{hf}Гц мс={dur}"
    if ftype == 3:
        lt, rt, dur = struct.unpack("<BBH", payload[:4])
        return f"Trigger триггеры={lt}/{rt} мс={dur}"
    if ftype == 4:
        return f"Sound   id={payload[0]} param={payload[1] if len(payload) > 1 else 0}"
    if ftype == 5:
        if len(payload) >= 13:
            speed, gear, rpm, g, thr, brk, slip, flags, max_rpm = struct.unpack(
                "<HBHhBBBBH", payload[:13])
        else:
            speed, gear, rpm, g, thr, brk, slip, flags = struct.unpack("<HBHhBBBB", payload[:11])
            max_rpm = 7500
        return (f"HUD     {speed} км/ч передача={gear} rpm={rpm}/{max_rpm} "
                f"g={g/100:.1f} газ={thr} тормоз={brk} slip={slip/40:.2f} флаги={flags}")
    if ftype == 6:
        return f"LED     rgb={tuple(payload[:3])}"
    if ftype == 7:
        return f"Status  code={payload[0]} detail={payload[1] if len(payload) > 1 else 0}"
    return f"?? type={ftype}"


def selftest() -> int:
    """Локальная проверка кодеков протокола (сеть не используется)."""
    failures = 0

    def check(condition: bool, name: str) -> None:
        nonlocal failures
        if condition:
            print(f"  [OK]   {name}")
        else:
            failures += 1
            print(f"  [FAIL] {name}")

    print("=== PhonePad sim selftest ===")

    packet = encode_state(buttons=BTN["a"] | BTN["start"], lt=128, rt=200,
                          lx=-1000, ly=500, rx=123, ry=-456, seq=4242)
    check(len(packet) == INPUT_PACKET_SIZE, "размер пакета ввода = 23 байта")
    check(packet[0] == INPUT_MAGIC and packet[1] == VERSION, "magic и версия")
    check(crc8(packet[:22]) == packet[22], "CRC сходится")

    broken = bytearray(packet)
    broken[10] ^= 0xFF
    check(crc8(bytes(broken[:22])) != broken[22], "испорченный пакет ломает CRC")

    telemetry = build_telemetry()
    check(len(telemetry) == TELEMETRY_PACKET_SIZE, "размер пакета телеметрии = 324 байта")
    check(struct.unpack_from("<f", telemetry, 16)[0] == 6500.0, "обороты на своём месте")
    check(telemetry[319] == 4, "передача на своём месте")

    payload = struct.pack("<HBHhBBBBH", 200, 0, 6500, 0, 100, 0, 0, 0, 7500)
    feedback = struct.pack("<BBBB", FEEDBACK_MAGIC, VERSION, 5, len(payload)) + payload
    ftype, payload = decode_feedback(feedback)
    check(ftype == 5 and len(payload) == 13, "HUD разбирается по объявленной длине")
    check("200 км/ч" in describe_feedback(feedback), "HUD описывается текстом")

    print()
    if failures == 0:
        print("ВСЕ ПРОВЕРКИ ПРОЙДЕНЫ")
        return 0
    print(f"ПРОВАЛЕНО проверок: {failures}")
    return 1


def main() -> int:
    parser = argparse.ArgumentParser(description="Симулятор телефона для PhonePad")
    parser.add_argument("--host", default="127.0.0.1", help="IP ПК")
    parser.add_argument("--port", type=int, default=8888, help="порт ввода на ПК")
    parser.add_argument("--feedback-port", type=int, default=8889, help="порт обратной связи на телефоне")
    parser.add_argument("--telemetry-port", type=int, default=5300, help="порт телеметрии FH6")
    parser.add_argument("--mode", choices=["state", "telemetry", "both", "selftest"], default="state")
    parser.add_argument("--duration", type=float, default=5.0, help="сколько секунд работать")
    parser.add_argument("--hz", type=float, default=100.0, help="частота отправки ввода")
    parser.add_argument("--drop-after", type=float, default=0.0,
                        help="через сколько секунд перестать слать ввод (проверка watchdog сервера)")
    args = parser.parse_args()

    if args.mode == "selftest":
        return selftest()

    out = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    out.settimeout(0.2)

    feedback = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    feedback.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    feedback.bind(("0.0.0.0", args.feedback_port))
    feedback.settimeout(0.01)

    print(f"PhonePad sim → {args.host}:{args.port} (режим: {args.mode}, {args.duration:.1f} c)")

    if args.mode in ("state", "both"):
        out.sendto(encode_control(2), (args.host, args.port))  # Hello

    seq = 0
    start = time.monotonic()
    period = 1.0 / max(1.0, args.hz)
    last_telemetry = 0.0

    while time.monotonic() - start < args.duration:
        now = time.monotonic() - start
        dropping = args.drop_after > 0 and now > args.drop_after

        if args.mode in ("state", "both") and not dropping:
            # Сценарий: плавное нарастание газа, руль по синусу, периодические нажатия.
            throttle = int(255 * min(1.0, now / 2.0))
            steer = int(700 * math.sin(now * 1.4))
            buttons = 0
            if int(now * 2) % 4 == 0:
                buttons |= BTN["a"]
            out.sendto(
                encode_state(buttons=buttons, lt=throttle, rt=0,
                             lx=steer, ly=0, rx=0, ry=0, seq=seq),
                (args.host, args.port))
            seq = (seq + 1) & 0xFFFF
        elif dropping and args.mode in ("state", "both") and now - args.drop_after < 0.2:
            print("  … ввод прекращён (проверка сброса пада на сервере)")

        if args.mode in ("telemetry", "both"):
            if now - last_telemetry > 0.05:
                last_telemetry = now
                gear = 1 + int((now * 2) % 6)
                out.sendto(
                    build_telemetry(rpm=4000 + (now * 800) % 3500,
                                   speed=40 + now * 5,
                                   throttle=200, brake=40,
                                   gear=gear, slip=1.2 + math.sin(now * 3) * 0.8,
                                   surface=0.3, rumble_strip=int(now) % 3 == 0),
                    (args.host, args.telemetry_port))

        # Читаем обратную связь
        try:
            while True:
                data, _ = feedback.recvfrom(512)
                print("  ←", describe_feedback(data))
        except socket.timeout:
            pass
        except BlockingIOError:
            pass

        time.sleep(period)

    if args.mode in ("state", "both"):
        out.sendto(encode_control(3), (args.host, args.port))  # Goodbye

    print("Готово.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
