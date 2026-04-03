#!/usr/bin/env python3
"""CodexBar Alternate Icon Generator v2.

Fixed: bracket direction, bolder strokes, stronger glow, better proportions.
"""

import math
import os
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
CR = 220  # corner radius

OUT_DIR = Path(__file__).parent


def rounded_mask(size, radius):
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    return mask


def draw_bracket_left(draw, tip_x, tip_y, half_h, stroke, color):
    """Draw < bracket: tip points LEFT."""
    draw.line([(tip_x, tip_y), (tip_x + half_h * 0.6, tip_y - half_h)], fill=color, width=stroke)
    draw.line([(tip_x, tip_y), (tip_x + half_h * 0.6, tip_y + half_h)], fill=color, width=stroke)
    # Round caps
    r = stroke // 2
    for pt in [(tip_x, tip_y), (tip_x + half_h * 0.6, tip_y - half_h), (tip_x + half_h * 0.6, tip_y + half_h)]:
        draw.ellipse([pt[0] - r, pt[1] - r, pt[0] + r, pt[1] + r], fill=color)


def draw_bracket_right(draw, tip_x, tip_y, half_h, stroke, color):
    """Draw > bracket: tip points RIGHT."""
    draw.line([(tip_x, tip_y), (tip_x - half_h * 0.6, tip_y - half_h)], fill=color, width=stroke)
    draw.line([(tip_x, tip_y), (tip_x - half_h * 0.6, tip_y + half_h)], fill=color, width=stroke)
    r = stroke // 2
    for pt in [(tip_x, tip_y), (tip_x - half_h * 0.6, tip_y - half_h), (tip_x - half_h * 0.6, tip_y + half_h)]:
        draw.ellipse([pt[0] - r, pt[1] - r, pt[0] + r, pt[1] + r], fill=color)


def draw_slash(draw, cx, cy, half_h, stroke, color):
    """Draw / slash."""
    draw.line(
        [(cx + half_h * 0.18, cy - half_h * 0.85), (cx - half_h * 0.18, cy + half_h * 0.85)],
        fill=color,
        width=stroke,
    )
    r = stroke // 2
    for pt in [(cx + half_h * 0.18, cy - half_h * 0.85), (cx - half_h * 0.18, cy + half_h * 0.85)]:
        draw.ellipse([pt[0] - r, pt[1] - r, pt[0] + r, pt[1] + r], fill=color)


def draw_code_symbol(draw, cx, cy, symbol_h, stroke, color, spread=1.0):
    """Draw </> centered at (cx, cy)."""
    half_h = symbol_h / 2
    gap = symbol_h * 0.55 * spread
    draw_bracket_left(draw, cx - gap, cy, half_h, stroke, color)
    draw_slash(draw, cx, cy, half_h, stroke, color)
    draw_bracket_right(draw, cx + gap, cy, half_h, stroke, color)


def draw_bars(draw, cx, cy, bar_w, bar_h, gap, count, color, radius=10):
    """Draw horizontal rounded bars."""
    total_h = count * bar_h + (count - 1) * gap
    start_y = cy - total_h / 2
    for i in range(count):
        y = start_y + i * (bar_h + gap)
        draw.rounded_rectangle(
            [cx - bar_w / 2, y, cx + bar_w / 2, y + bar_h], radius=radius, fill=color
        )


def gradient_v(size, top, bot):
    img = Image.new("RGBA", (size, size))
    px = img.load()
    for y in range(size):
        t = y / size
        c = tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(3))
        for x in range(size):
            px[x, y] = (*c, 255)
    return img


def radial_grad(size, center, edge, cx_f=0.5, cy_f=0.45):
    img = Image.new("RGBA", (size, size))
    px = img.load()
    cxp, cyp = int(size * cx_f), int(size * cy_f)
    max_d = math.sqrt(cxp**2 + cyp**2) * 1.3
    for y in range(size):
        for x in range(size):
            d = math.sqrt((x - cxp) ** 2 + (y - cyp) ** 2)
            t = min(d / max_d, 1.0)
            c = tuple(int(center[i] + (edge[i] - center[i]) * t) for i in range(3))
            px[x, y] = (*c, 255)
    return img


def glow_layer(elements, glow_color, radius=25, passes=5):
    """Create strong glow from element alpha."""
    alpha = elements.split()[3]
    glow = Image.new("RGBA", elements.size, (0, 0, 0, 0))
    blurred = alpha.filter(ImageFilter.GaussianBlur(radius))
    layer = Image.new("RGBA", elements.size, (*glow_color, 0))
    layer.putalpha(blurred)
    for _ in range(passes):
        glow = Image.alpha_composite(glow, layer)
    return glow


def apply_mask(img, mask):
    result = img.copy()
    result.putalpha(mask)
    return result


def add_scanlines(img, spacing=6, alpha=25):
    """Add subtle horizontal scanlines for cyberpunk feel."""
    overlay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    for y in range(0, img.size[1], spacing):
        draw.line([(0, y), (img.size[0], y)], fill=(0, 0, 0, alpha), width=1)
    return Image.alpha_composite(img, overlay)


# =============================================================================
# Monochrome
# =============================================================================

MONO_CONFIGS = [
    # (bg, fg, label)
    ((255, 255, 255), (25, 25, 30), "white-black"),
    ((18, 18, 22), (235, 235, 240), "black-white"),
    ((242, 240, 235), (55, 50, 45), "cream-charcoal"),
    ((30, 32, 38), (195, 198, 205), "slate-silver"),
    ((170, 172, 178), (12, 12, 12), "grey-black"),
    ((40, 42, 50), (225, 228, 235), "darkslate-offwhite"),
    ((255, 252, 245), (80, 60, 40), "ivory-brown"),
    ((15, 15, 18), (255, 255, 255), "trueblack-white"),
    ((50, 55, 65), (180, 200, 220), "bluegrey-ice"),
    ((245, 245, 250), (45, 45, 55), "snow-ink"),
]


def gen_monochrome(round_num):
    cfg = MONO_CONFIGS[(round_num - 1) % len(MONO_CONFIGS)]
    bg_c, fg_c, label = cfg

    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    draw.rounded_rectangle([0, 0, SIZE - 1, SIZE - 1], radius=CR, fill=(*bg_c, 255))

    sym_cy = SIZE * 0.37
    stroke = int(SIZE * 0.055)
    draw_code_symbol(draw, SIZE / 2, sym_cy, SIZE * 0.34, stroke, fg_c)
    draw_bars(draw, SIZE / 2, SIZE * 0.70, SIZE * 0.46, SIZE * 0.042, SIZE * 0.038, 3, fg_c, radius=12)

    mask = rounded_mask(SIZE, CR)
    return apply_mask(img, mask), label


# =============================================================================
# Neon
# =============================================================================

NEON_SCHEMES = {
    "purple": [
        {"bg_c": (35, 8, 55), "bg_e": (12, 4, 25), "fg": (210, 60, 255), "bar": (160, 80, 255), "glow": (200, 50, 255), "scan": True},
        {"bg_c": (25, 5, 45), "bg_e": (8, 2, 18), "fg": (255, 100, 230), "bar": (200, 60, 255), "glow": (230, 80, 255), "scan": False},
        {"bg_c": (40, 12, 65), "bg_e": (15, 5, 30), "fg": (180, 40, 255), "bar": (140, 60, 230), "glow": (170, 40, 255), "scan": True},
        {"bg_c": (20, 3, 35), "bg_e": (5, 1, 12), "fg": (255, 120, 255), "bar": (200, 80, 255), "glow": (255, 100, 255), "scan": False},
        {"bg_c": (45, 15, 70), "bg_e": (18, 6, 32), "fg": (190, 50, 240), "bar": (150, 70, 220), "glow": (180, 50, 240), "scan": True},
        {"bg_c": (30, 8, 50), "bg_e": (10, 3, 20), "fg": (230, 80, 255), "bar": (180, 50, 255), "glow": (220, 70, 255), "scan": False},
        {"bg_c": (22, 4, 40), "bg_e": (6, 1, 15), "fg": (255, 140, 255), "bar": (210, 90, 255), "glow": (240, 120, 255), "scan": True},
        {"bg_c": (38, 10, 58), "bg_e": (14, 4, 26), "fg": (200, 50, 240), "bar": (160, 60, 230), "glow": (190, 50, 240), "scan": False},
        {"bg_c": (28, 6, 48), "bg_e": (9, 2, 18), "fg": (240, 90, 255), "bar": (190, 60, 250), "glow": (230, 80, 255), "scan": True},
        {"bg_c": (18, 2, 32), "bg_e": (4, 0, 10), "fg": (255, 110, 240), "bar": (220, 70, 255), "glow": (250, 100, 255), "scan": False},
    ],
    "green": [
        {"bg_c": (8, 38, 30), "bg_e": (3, 15, 12), "fg": (0, 255, 180), "bar": (50, 230, 150), "glow": (0, 255, 160), "scan": True},
        {"bg_c": (5, 30, 25), "bg_e": (2, 12, 8), "fg": (80, 255, 200), "bar": (30, 240, 170), "glow": (60, 255, 190), "scan": False},
        {"bg_c": (10, 42, 35), "bg_e": (4, 18, 14), "fg": (0, 240, 160), "bar": (40, 220, 140), "glow": (0, 240, 150), "scan": True},
        {"bg_c": (3, 25, 20), "bg_e": (1, 8, 5), "fg": (100, 255, 210), "bar": (60, 240, 180), "glow": (80, 255, 200), "scan": False},
        {"bg_c": (12, 45, 38), "bg_e": (5, 20, 16), "fg": (0, 250, 170), "bar": (50, 225, 145), "glow": (0, 250, 160), "scan": True},
        {"bg_c": (6, 32, 26), "bg_e": (2, 13, 10), "fg": (60, 255, 195), "bar": (20, 235, 165), "glow": (50, 255, 185), "scan": False},
        {"bg_c": (4, 28, 22), "bg_e": (1, 10, 7), "fg": (90, 255, 205), "bar": (50, 240, 175), "glow": (70, 255, 195), "scan": True},
        {"bg_c": (9, 40, 32), "bg_e": (3, 16, 13), "fg": (10, 245, 165), "bar": (45, 225, 148), "glow": (10, 245, 155), "scan": False},
        {"bg_c": (7, 35, 28), "bg_e": (2, 14, 11), "fg": (70, 255, 198), "bar": (35, 238, 168), "glow": (55, 255, 188), "scan": True},
        {"bg_c": (2, 22, 18), "bg_e": (0, 6, 4), "fg": (110, 255, 215), "bar": (70, 242, 185), "glow": (90, 255, 205), "scan": False},
    ],
    "orange": [
        {"bg_c": (48, 22, 4), "bg_e": (22, 8, 1), "fg": (255, 160, 30), "bar": (255, 130, 50), "glow": (255, 150, 20), "scan": True},
        {"bg_c": (40, 18, 2), "bg_e": (18, 6, 0), "fg": (255, 190, 60), "bar": (255, 150, 40), "glow": (255, 180, 50), "scan": False},
        {"bg_c": (52, 25, 5), "bg_e": (25, 10, 2), "fg": (255, 140, 20), "bar": (255, 110, 40), "glow": (255, 130, 15), "scan": True},
        {"bg_c": (35, 14, 1), "bg_e": (14, 4, 0), "fg": (255, 200, 80), "bar": (255, 160, 50), "glow": (255, 190, 70), "scan": False},
        {"bg_c": (55, 28, 6), "bg_e": (28, 12, 3), "fg": (255, 150, 25), "bar": (255, 120, 45), "glow": (255, 140, 20), "scan": True},
        {"bg_c": (42, 20, 3), "bg_e": (20, 7, 1), "fg": (255, 175, 50), "bar": (255, 140, 45), "glow": (255, 165, 40), "scan": False},
        {"bg_c": (32, 12, 0), "bg_e": (12, 3, 0), "fg": (255, 210, 90), "bar": (255, 170, 55), "glow": (255, 200, 80), "scan": True},
        {"bg_c": (50, 24, 5), "bg_e": (24, 9, 2), "fg": (255, 145, 22), "bar": (255, 115, 42), "glow": (255, 135, 18), "scan": False},
        {"bg_c": (44, 21, 3), "bg_e": (21, 8, 1), "fg": (255, 180, 55), "bar": (255, 145, 48), "glow": (255, 170, 45), "scan": True},
        {"bg_c": (28, 10, 0), "bg_e": (8, 2, 0), "fg": (255, 215, 100), "bar": (255, 175, 60), "glow": (255, 205, 90), "scan": False},
    ],
}


def gen_neon(round_num, color):
    configs = NEON_SCHEMES[color]
    cfg = configs[(round_num - 1) % len(configs)]

    bg = radial_grad(SIZE, cfg["bg_c"], cfg["bg_e"])
    mask = rounded_mask(SIZE, CR)
    bg = apply_mask(bg, mask)

    # Elements on transparent layer
    el = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(el)

    sym_cy = SIZE * 0.37
    stroke = int(SIZE * 0.048)
    draw_code_symbol(draw, SIZE / 2, sym_cy, SIZE * 0.34, stroke, cfg["fg"], spread=1.0)
    draw_bars(draw, SIZE / 2, SIZE * 0.70, SIZE * 0.46, SIZE * 0.040, SIZE * 0.036, 3, cfg["bar"], radius=10)

    # Strong glow
    glow = glow_layer(el, cfg["glow"], radius=30, passes=6)
    result = Image.alpha_composite(bg, glow)
    result = Image.alpha_composite(result, el)

    if cfg["scan"]:
        result = add_scanlines(result, spacing=5, alpha=18)

    return result


def main():
    rounds = int(sys.argv[1]) if len(sys.argv) > 1 else 10
    print(f"=== Icon Generator v2 — {rounds} rounds ===\n")

    for r in range(1, rounds + 1):
        print(f"Round {r}/{rounds}:")

        mono, label = gen_monochrome(r)
        p = OUT_DIR / "monochrome" / "rounds" / f"round_{r:02d}_{label}.png"
        mono.save(str(p), "PNG")
        print(f"  Mono: {p.name}")

        for color in ["purple", "green", "orange"]:
            neon = gen_neon(r, color)
            p = OUT_DIR / f"neon-{color}" / "rounds" / f"round_{r:02d}.png"
            neon.save(str(p), "PNG")
            print(f"  Neon-{color}: {p.name}")

        print()

    print("Done.")


if __name__ == "__main__":
    main()
