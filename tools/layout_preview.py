#!/usr/bin/env python3
"""
Превью раскладок PhonePad без устройства и без сборки приложения.

Рисует те же нормализованные координаты, что и `ios/Sources/PadLayout.swift`,
с тем же запасом сверху под панель статуса (`topReserved`). Нужен, чтобы
быстро прикинуть, как раскладка ляжет на экран телефона.

Запуск:
  python3 tools/layout_preview.py --layout racing --out preview.png
"""

import argparse
import os

# --- геометрия ------------------------------------------------------------

# Нормализованные раскладки (x, y, w, h) — должны совпадать с PadLayout.swift.
LAYOUTS = {
    "full": {
        "ls":   (0.075, 0.50, 0.20, 0.38),
        "dpad_up":    (0.108, 0.19, 0.074, 0.074),
        "dpad_down":  (0.108, 0.375, 0.074, 0.074),
        "dpad_left":  (0.062, 0.283, 0.074, 0.074),
        "dpad_right": (0.154, 0.283, 0.074, 0.074),
        "rs":   (0.70, 0.48, 0.20, 0.38),
        "btn_y": (0.795, 0.13, 0.07, 0.07),
        "btn_x": (0.715, 0.21, 0.07, 0.07),
        "btn_b": (0.875, 0.21, 0.07, 0.07),
        "btn_a": (0.795, 0.29, 0.07, 0.07),
        "lb":   (0.33, 0.02, 0.13, 0.075),
        "rb":   (0.60, 0.02, 0.13, 0.075),
        "lt":   (0.0, 0.22, 0.042, 0.72),
        "rt":   (0.958, 0.22, 0.042, 0.72),
        "back": (0.475, 0.02, 0.055, 0.075),
        "start": (0.545, 0.02, 0.055, 0.075),
        "guide": (0.49, 0.13, 0.06, 0.06),
    },
    "racing": {
        "ls":   (0.03, 0.19, 0.40, 0.73),
        "lt":   (0.72, 0.19, 0.11, 0.73),
        "rt":   (0.86, 0.19, 0.11, 0.73),
        "btn_a": (0.55, 0.58, 0.12, 0.12),
        "btn_b": (0.55, 0.42, 0.12, 0.12),
        "lb":   (0.55, 0.26, 0.12, 0.12),
        "rb":   (0.55, 0.10, 0.12, 0.12),
        "start": (0.55, 0.78, 0.12, 0.12),
    },
}

LABELS = {
    "ls": "L", "rs": "R",
    "dpad_up": "▲", "dpad_down": "▼", "dpad_left": "◀", "dpad_right": "▶",
    "btn_y": "Y", "btn_x": "X", "btn_b": "B", "btn_a": "A",
    "lb": "HB", "rb": "RST", "lt": "LT", "rt": "RT",
    "back": "≡", "start": "▷", "guide": "PS",
}

RACING_LABELS = {"lt": "ТОРМ", "rt": "ГАЗ", "lb": "HB", "rb": "RST", "ls": "РУЛЬ"}

STICKS = {"ls", "rs"}
STICK_RADIUS = {"full": {"ls": 0.085, "rs": 0.085},
                "racing": {"ls": 0.16, "rs": 0.085}}
TRIGGERS = {"lt", "rt"}
ROUND = {"btn_y", "btn_x", "btn_b", "btn_a", "lb", "rb", "guide"}

SCREEN_PT = (874, 402)     # iPhone 16 Pro в ландшафте, в пунктах
SCALE = 3                 # @3x для наглядности
TOP_RESERVED_PT = 58      # запас под панель статуса


def font(size_pt):
    from PIL import ImageFont
    size = max(8, int(size_pt * SCALE))
    for name in ("segoeuib.ttf", "arialbd.ttf", "arial.ttf"):
        path = os.path.join("C:\\Windows\\Fonts", name)
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size)
            except OSError:
                continue
    return ImageFont.load_default()


def fit_font(text, max_pt, width_px):
    """Подбирает кегль так, чтобы текст поместился по ширине."""
    size = max_pt
    f = font(size)
    while size > 7 and f.getlength(text) > width_px:
        size -= 1
        f = font(size)
    return f


def main() -> int:
    parser = argparse.ArgumentParser(description="Превью раскладок PhonePad")
    parser.add_argument("--layout", choices=list(LAYOUTS.keys()), default="racing")
    parser.add_argument("--out", default="layout-preview.png")
    args = parser.parse_args()

    from PIL import Image, ImageDraw

    w = SCREEN_PT[0] * SCALE
    h = SCREEN_PT[1] * SCALE
    top = TOP_RESERVED_PT * SCALE
    usable = h - top

    img = Image.new("RGB", (w, h), (0, 0, 0))
    d = ImageDraw.Draw(img)

    # Панель статуса приложения + компактный HUD внутри неё.
    d.rounded_rectangle((12 * SCALE, 6 * SCALE, w - 12 * SCALE, 48 * SCALE),
                        radius=18 * SCALE, fill=(20, 20, 22))
    d.text((30 * SCALE, 18 * SCALE), "нет связи", font=font(12), fill=(220, 220, 225))
    d.ellipse((18 * SCALE, 22 * SCALE, 26 * SCALE, 30 * SCALE), fill=(240, 160, 40))
    d.text((96 * SCALE, 16 * SCALE), "0", font=font(18), fill=(255, 255, 255))
    d.text((116 * SCALE, 21 * SCALE), "км/ч", font=font(9), fill=(150, 150, 155))
    # Кнопки справа.
    for i, label in enumerate(["Гиро", "((·))", "⚙"]):
        x = w - (250 - i * 70) * SCALE
        d.ellipse((x, 12 * SCALE, x + 32 * SCALE, 44 * SCALE), fill=(42, 42, 46))
        d.text((x + 8 * SCALE, 20 * SCALE), label, font=font(11), fill=(235, 235, 240))

    for cid, (nx, ny, nw, nh) in LAYOUTS[args.layout].items():
        x = nx * w
        y = top + ny * usable
        bw = nw * w
        bh = nh * usable

        if cid in TRIGGERS:
            d.rounded_rectangle((x, y, x + bw, y + bh), radius=8 * SCALE,
                                outline=(70, 70, 78), width=1)
        elif cid in STICKS:
            d.rounded_rectangle((x, y, x + bw, y + bh), radius=18 * SCALE,
                                fill=(14, 14, 16), outline=(34, 34, 38))
            # Радиус стика — доля от короткой стороны экрана (как в PadLayout).
            radius = STICK_RADIUS[args.layout].get(cid, 0.085) * min(w, usable)
            cx, cy = x + bw / 2, y + bh / 2
            d.ellipse((cx - radius, cy - radius, cx + radius, cy + radius),
                      fill=(34, 34, 40), outline=(62, 62, 70), width=2)
            d.ellipse((cx - radius * 0.38, cy - radius * 0.38,
                       cx + radius * 0.38, cy + radius * 0.38), fill=(90, 90, 100))
        else:
            if cid in ROUND:
                d.ellipse((x, y, x + bw, y + bh), fill=(30, 30, 34),
                          outline=(80, 80, 88), width=2)
            else:
                d.rounded_rectangle((x, y, x + bw, y + bh), radius=8 * SCALE,
                                    fill=(30, 30, 34), outline=(80, 80, 88), width=2)

        label = LABELS.get(cid, "")
        if args.layout == "racing":
            label = RACING_LABELS.get(cid, label)
        if not label:
            continue

        if cid in TRIGGERS:
            lf = (x, y, x + bw, y + min(22 * SCALE, bh * 0.2))
        elif cid in STICKS:
            lf = (x, y + bh - min(20 * SCALE, bh * 0.14), x + bw,
                  y + bh)
        else:
            lf = (x, y, x + bw, y + bh)

        max_pt = 15 if cid in TRIGGERS else (14 if cid in STICKS else 18)
        f = fit_font(label, max_pt, lf[2] - lf[0])
        tw = f.getlength(label)
        d.text((lf[0] + (lf[2] - lf[0] - tw) / 2, lf[1] + 2 * SCALE), label,
               font=f, fill=(225, 225, 232))

    img.save(args.out)
    print(f"Превью сохранено: {args.out} ({w}x{h})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
