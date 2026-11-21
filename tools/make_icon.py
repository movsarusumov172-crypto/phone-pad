#!/usr/bin/env python3
"""
Генерация иконки приложения PhonePad (1024×1024, PNG).

Скрипт хранится в репозитории, чтобы иконку можно было перегенерировать
в любой момент: `python tools/make_icon.py`.

Оформление: тёмный корпус, световая полоса сверху (как у DualSense),
D-pad слева, цветные кнопки справа и два аналоговых стика.
"""

import os
from PIL import Image, ImageDraw

SIZE = 1024
OUT = os.path.join(os.path.dirname(__file__), "..", "ios", "Resources",
                   "Assets.xcassets", "AppIcon.appiconset", "AppIcon-1024.png")

BG_TOP = (26, 32, 44)
BG_BOTTOM = (11, 14, 20)
BODY = (32, 39, 52)
BODY_EDGE = (62, 73, 94)
STICK = (44, 53, 69)
STICK_RING = (96, 110, 134)
WHITE = (222, 229, 240)
LIGHTBAR = (236, 241, 249)

BUTTONS = {
    # Xbox-раскладка: Y сверху, X слева, B справа, A снизу.
    "Y": ((790, 438), (245, 197, 66)),
    "X": ((710, 516), (76, 155, 232)),
    "B": ((870, 516), (226, 87, 76)),
    "A": ((790, 594), (87, 192, 138)),
}


def vertical_gradient(width: int, height: int, top, bottom) -> Image.Image:
    img = Image.new("RGB", (1, height))
    px = img.load()
    for y in range(height):
        t = y / max(1, height - 1)
        px[0, y] = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
    return img.resize((width, height), Image.BILINEAR)


def rounded_rect(draw, box, radius, fill=None, outline=None, width=0):
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def main() -> None:
    img = vertical_gradient(SIZE, SIZE, BG_TOP, BG_BOTTOM).convert("RGBA")
    layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)

    # Корпус контроллера.
    rounded_rect(d, (120, 276, 904, 800), 150, fill=BODY, outline=BODY_EDGE, width=4)

    # Световая полоса.
    rounded_rect(d, (430, 318, 594, 352), 17, fill=LIGHTBAR)

    # D-pad.
    rounded_rect(d, (258, 424, 318, 556), 18, fill=WHITE)
    rounded_rect(d, (220, 462, 356, 518), 18, fill=WHITE)

    # Аналоговые стики.
    for cx, cy in ((280, 690), (660, 690)):
        d.ellipse((cx - 88, cy - 88, cx + 88, cy + 88), fill=STICK, outline=STICK_RING, width=6)
        d.ellipse((cx - 52, cy - 52, cx + 52, cy + 52), fill=(58, 69, 88), outline=STICK_RING, width=4)

    # Цветные кнопки.
    for (cx, cy), color in BUTTONS.values():
        d.ellipse((cx - 44, cy - 44, cx + 44, cy + 44), fill=color)

    # Мягкая тень под корпусом.
    shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.rounded_rectangle((134, 292, 918, 820), 150, fill=(0, 0, 0, 110))
    shadow = shadow.filter(__import__("PIL.ImageFilter", fromlist=["ImageFilter"]).GaussianBlur(26))

    out = Image.alpha_composite(img, shadow)
    out = Image.alpha_composite(out, layer).convert("RGB")

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    out.save(OUT, "PNG", optimize=True)
    print(f"Иконка сохранена: {os.path.normpath(OUT)}")


if __name__ == "__main__":
    main()
