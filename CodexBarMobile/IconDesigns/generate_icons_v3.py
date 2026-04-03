#!/usr/bin/env python3
"""CodexBar Icon Generator v3 — refined neon glow, crisp elements."""

import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
CR = 220
OUT_DIR = Path(__file__).parent


def rounded_mask(size, radius):
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    return mask


def draw_bracket_left(draw, tip_x, tip_y, half_h, stroke, color):
    draw.line([(tip_x, tip_y), (tip_x + half_h * 0.6, tip_y - half_h)], fill=color, width=stroke)
    draw.line([(tip_x, tip_y), (tip_x + half_h * 0.6, tip_y + half_h)], fill=color, width=stroke)
    r = stroke // 2
    for pt in [(tip_x, tip_y), (tip_x + half_h * 0.6, tip_y - half_h), (tip_x + half_h * 0.6, tip_y + half_h)]:
        draw.ellipse([pt[0] - r, pt[1] - r, pt[0] + r, pt[1] + r], fill=color)


def draw_bracket_right(draw, tip_x, tip_y, half_h, stroke, color):
    draw.line([(tip_x, tip_y), (tip_x - half_h * 0.6, tip_y - half_h)], fill=color, width=stroke)
    draw.line([(tip_x, tip_y), (tip_x - half_h * 0.6, tip_y + half_h)], fill=color, width=stroke)
    r = stroke // 2
    for pt in [(tip_x, tip_y), (tip_x - half_h * 0.6, tip_y - half_h), (tip_x - half_h * 0.6, tip_y + half_h)]:
        draw.ellipse([pt[0] - r, pt[1] - r, pt[0] + r, pt[1] + r], fill=color)


def draw_slash(draw, cx, cy, half_h, stroke, color):
    draw.line(
        [(cx + half_h * 0.18, cy - half_h * 0.85), (cx - half_h * 0.18, cy + half_h * 0.85)],
        fill=color, width=stroke,
    )
    r = stroke // 2
    for pt in [(cx + half_h * 0.18, cy - half_h * 0.85), (cx - half_h * 0.18, cy + half_h * 0.85)]:
        draw.ellipse([pt[0] - r, pt[1] - r, pt[0] + r, pt[1] + r], fill=color)


def draw_code_symbol(draw, cx, cy, symbol_h, stroke, color, spread=1.0):
    half_h = symbol_h / 2
    gap = symbol_h * 0.55 * spread
    draw_bracket_left(draw, cx - gap, cy, half_h, stroke, color)
    draw_slash(draw, cx, cy, half_h, stroke, color)
    draw_bracket_right(draw, cx + gap, cy, half_h, stroke, color)


def draw_bars(draw, cx, cy, bar_w, bar_h, gap, count, color, radius=10):
    total_h = count * bar_h + (count - 1) * gap
    start_y = cy - total_h / 2
    for i in range(count):
        y = start_y + i * (bar_h + gap)
        draw.rounded_rectangle([cx - bar_w / 2, y, cx + bar_w / 2, y + bar_h], radius=radius, fill=color)


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


def subtle_glow(elements, glow_color, radius=14, passes=3):
    """Subtle glow — tight radius, few passes. Elements stay crisp."""
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


def add_scanlines(img, spacing=5, alpha=15):
    overlay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    for y in range(0, img.size[1], spacing):
        draw.line([(0, y), (img.size[0], y)], fill=(0, 0, 0, alpha), width=1)
    return Image.alpha_composite(img, overlay)


def draw_elements(size, fg_color, bar_color, stroke_w, spread=1.05):
    """Draw </> + bars on a transparent layer."""
    el = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(el)
    draw_code_symbol(draw, size / 2, size * 0.37, size * 0.34, stroke_w, fg_color, spread=spread)
    draw_bars(draw, size / 2, size * 0.70, size * 0.46, size * 0.042, size * 0.036, 3, bar_color, radius=12)
    return el


# =============================================================================
# Monochrome configs — 10 unique
# =============================================================================
MONO = [
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


# =============================================================================
# Neon configs — 10 per color, varied glow/bg/scan
# =============================================================================
def neon_configs(color):
    if color == "purple":
        base = [
            ((35, 8, 55), (12, 4, 25), (210, 60, 255), (160, 80, 255), (200, 50, 255), 14, 3, True),
            ((25, 5, 45), (8, 2, 18), (255, 100, 230), (200, 60, 255), (230, 80, 255), 12, 2, False),
            ((40, 12, 65), (15, 5, 30), (180, 40, 255), (140, 60, 230), (170, 40, 255), 16, 3, True),
            ((20, 3, 35), (5, 1, 12), (255, 120, 255), (200, 80, 255), (255, 100, 255), 10, 2, False),
            ((45, 15, 70), (18, 6, 32), (190, 50, 240), (150, 70, 220), (180, 50, 240), 15, 3, True),
            ((30, 8, 50), (10, 3, 20), (230, 80, 255), (180, 50, 255), (220, 70, 255), 13, 2, False),
            ((22, 4, 40), (6, 1, 15), (255, 140, 255), (210, 90, 255), (240, 120, 255), 11, 3, True),
            ((38, 10, 58), (14, 4, 26), (200, 50, 240), (160, 60, 230), (190, 50, 240), 14, 2, False),
            ((28, 6, 48), (9, 2, 18), (240, 90, 255), (190, 60, 250), (230, 80, 255), 12, 3, True),
            ((18, 2, 32), (4, 0, 10), (255, 110, 240), (220, 70, 255), (250, 100, 255), 10, 2, False),
        ]
    elif color == "green":
        base = [
            ((8, 38, 30), (3, 15, 12), (0, 255, 180), (50, 230, 150), (0, 255, 160), 14, 3, True),
            ((5, 30, 25), (2, 12, 8), (80, 255, 200), (30, 240, 170), (60, 255, 190), 12, 2, False),
            ((10, 42, 35), (4, 18, 14), (0, 240, 160), (40, 220, 140), (0, 240, 150), 16, 3, True),
            ((3, 25, 20), (1, 8, 5), (100, 255, 210), (60, 240, 180), (80, 255, 200), 10, 2, False),
            ((12, 45, 38), (5, 20, 16), (0, 250, 170), (50, 225, 145), (0, 250, 160), 15, 3, True),
            ((6, 32, 26), (2, 13, 10), (60, 255, 195), (20, 235, 165), (50, 255, 185), 13, 2, False),
            ((4, 28, 22), (1, 10, 7), (90, 255, 205), (50, 240, 175), (70, 255, 195), 11, 3, True),
            ((9, 40, 32), (3, 16, 13), (10, 245, 165), (45, 225, 148), (10, 245, 155), 14, 2, False),
            ((7, 35, 28), (2, 14, 11), (70, 255, 198), (35, 238, 168), (55, 255, 188), 12, 3, True),
            ((2, 22, 18), (0, 6, 4), (110, 255, 215), (70, 242, 185), (90, 255, 205), 10, 2, False),
        ]
    else:  # orange
        base = [
            ((48, 22, 4), (22, 8, 1), (255, 160, 30), (255, 130, 50), (255, 150, 20), 14, 3, True),
            ((40, 18, 2), (18, 6, 0), (255, 190, 60), (255, 150, 40), (255, 180, 50), 12, 2, False),
            ((52, 25, 5), (25, 10, 2), (255, 140, 20), (255, 110, 40), (255, 130, 15), 16, 3, True),
            ((35, 14, 1), (14, 4, 0), (255, 200, 80), (255, 160, 50), (255, 190, 70), 10, 2, False),
            ((55, 28, 6), (28, 12, 3), (255, 150, 25), (255, 120, 45), (255, 140, 20), 15, 3, True),
            ((42, 20, 3), (20, 7, 1), (255, 175, 50), (255, 140, 45), (255, 165, 40), 13, 2, False),
            ((32, 12, 0), (12, 3, 0), (255, 210, 90), (255, 170, 55), (255, 200, 80), 11, 3, True),
            ((50, 24, 5), (24, 9, 2), (255, 145, 22), (255, 115, 42), (255, 135, 18), 14, 2, False),
            ((44, 21, 3), (21, 8, 1), (255, 180, 55), (255, 145, 48), (255, 170, 45), 12, 3, True),
            ((28, 10, 0), (8, 2, 0), (255, 215, 100), (255, 175, 60), (255, 205, 90), 10, 2, False),
        ]
    return base


def gen_neon(round_num, color):
    cfgs = neon_configs(color)
    cfg = cfgs[(round_num - 1) % len(cfgs)]
    bg_c, bg_e, fg, bar_c, glow_c, glow_r, glow_p, scan = cfg

    bg = radial_grad(SIZE, bg_c, bg_e)
    mask = rounded_mask(SIZE, CR)
    bg = apply_mask(bg, mask)

    stroke = int(SIZE * 0.05)
    el = draw_elements(SIZE, fg, bar_c, stroke, spread=1.05)

    # Subtle glow behind, then sharp elements on top
    glow = subtle_glow(el, glow_c, radius=glow_r, passes=glow_p)
    result = Image.alpha_composite(bg, glow)
    result = Image.alpha_composite(result, el)  # crisp layer on top

    if scan:
        result = add_scanlines(result, spacing=5, alpha=15)

    return result


def main():
    rounds = int(sys.argv[1]) if len(sys.argv) > 1 else 10
    print(f"=== Icon Generator v3 (refined glow) — {rounds} rounds ===\n")

    for r in range(1, rounds + 1):
        print(f"Round {r}/{rounds}:")
        # Mono
        bg_c, fg_c, label = MONO[(r - 1) % len(MONO)]
        img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
        draw = ImageDraw.Draw(img)
        draw.rounded_rectangle([0, 0, SIZE - 1, SIZE - 1], radius=CR, fill=(*bg_c, 255))
        stroke = int(SIZE * 0.055)
        draw_code_symbol(draw, SIZE / 2, SIZE * 0.37, SIZE * 0.34, stroke, fg_c)
        draw_bars(draw, SIZE / 2, SIZE * 0.70, SIZE * 0.46, SIZE * 0.042, SIZE * 0.038, 3, fg_c, radius=12)
        img = apply_mask(img, rounded_mask(SIZE, CR))
        p = OUT_DIR / "monochrome" / "rounds" / f"v3_round_{r:02d}_{label}.png"
        img.save(str(p), "PNG")
        print(f"  Mono: {p.name}")

        for color in ["purple", "green", "orange"]:
            neon = gen_neon(r, color)
            p = OUT_DIR / f"neon-{color}" / "rounds" / f"v3_round_{r:02d}.png"
            neon.save(str(p), "PNG")
            print(f"  Neon-{color}: {p.name}")
        print()

    print("Done.")


if __name__ == "__main__":
    main()
