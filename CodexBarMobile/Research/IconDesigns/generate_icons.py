#!/usr/bin/env python3
"""CodexBar Alternate Icon Generator.

Generates 4 icon styles:
- Monochrome: clean black/white minimalist
- Neon Purple: cyberpunk with purple/magenta glow
- Neon Green: cyberpunk with green/cyan glow
- Neon Orange: cyberpunk with orange/amber glow

Each round saves to: {style}/rounds/round_{N}.png
Best picks go to: {style}/final.png
"""

import math
import os
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

SIZE = 1024
CORNER_RADIUS = 220  # iOS icon corner radius at 1024px

OUT_DIR = Path(__file__).parent


def rounded_rect_mask(size, radius):
    """Create a rounded rectangle mask."""
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    return mask


def draw_code_brackets(draw, cx, cy, bracket_h, stroke_w, color, slash_offset=0):
    """Draw </> code brackets centered at (cx, cy)."""
    half_h = bracket_h / 2
    # Left bracket <
    lx = cx - bracket_h * 0.52 + slash_offset
    draw.line([(lx, cy), (lx - half_h * 0.55, cy - half_h)], fill=color, width=stroke_w)
    draw.line([(lx, cy), (lx - half_h * 0.55, cy + half_h)], fill=color, width=stroke_w)

    # Right bracket >
    rx = cx + bracket_h * 0.52 + slash_offset
    draw.line([(rx, cy), (rx + half_h * 0.55, cy - half_h)], fill=color, width=stroke_w)
    draw.line([(rx, cy), (rx + half_h * 0.55, cy + half_h)], fill=color, width=stroke_w)

    # Slash /
    sx = cx + slash_offset
    draw.line(
        [(sx + bracket_h * 0.12, cy - half_h * 0.9), (sx - bracket_h * 0.12, cy + half_h * 0.9)],
        fill=color,
        width=stroke_w,
    )


def draw_bars(draw, cx, cy, bar_w, bar_h, gap, count, color, radius=0):
    """Draw horizontal bars centered at (cx, cy)."""
    total_h = count * bar_h + (count - 1) * gap
    start_y = cy - total_h / 2
    for i in range(count):
        y = start_y + i * (bar_h + gap)
        x0 = cx - bar_w / 2
        x1 = cx + bar_w / 2
        if radius > 0:
            draw.rounded_rectangle([x0, y, x1, y + bar_h], radius=radius, fill=color)
        else:
            draw.rectangle([x0, y, x1, y + bar_h], fill=color)


def make_gradient(size, color_top, color_bottom):
    """Create a vertical gradient image."""
    img = Image.new("RGBA", (size, size))
    for y in range(size):
        t = y / size
        r = int(color_top[0] + (color_bottom[0] - color_top[0]) * t)
        g = int(color_top[1] + (color_bottom[1] - color_top[1]) * t)
        b = int(color_top[2] + (color_bottom[2] - color_top[2]) * t)
        a = int(color_top[3] + (color_bottom[3] - color_top[3]) * t) if len(color_top) > 3 else 255
        for x in range(size):
            img.putpixel((x, y), (r, g, b, a))
    return img


def make_radial_gradient(size, center_color, edge_color, cx=0.5, cy=0.45):
    """Create a radial gradient image."""
    img = Image.new("RGBA", (size, size))
    pixels = img.load()
    center_x = int(size * cx)
    center_y = int(size * cy)
    max_dist = math.sqrt(center_x**2 + center_y**2) * 1.2
    for y in range(size):
        for x in range(size):
            dist = math.sqrt((x - center_x) ** 2 + (y - center_y) ** 2)
            t = min(dist / max_dist, 1.0)
            r = int(center_color[0] + (edge_color[0] - center_color[0]) * t)
            g = int(center_color[1] + (edge_color[1] - center_color[1]) * t)
            b = int(center_color[2] + (edge_color[2] - center_color[2]) * t)
            pixels[x, y] = (r, g, b, 255)
    return img


def add_glow(img, glow_color, radius=20, intensity=0.6):
    """Add a glow effect around non-transparent content."""
    alpha = img.split()[3]
    glow = Image.new("RGBA", img.size, (*glow_color, 0))
    glow_alpha = alpha.filter(ImageFilter.GaussianBlur(radius))
    glow.putalpha(glow_alpha)
    # Boost glow
    result = Image.new("RGBA", img.size, (0, 0, 0, 0))
    for _ in range(int(intensity * 4)):
        result = Image.alpha_composite(result, glow)
    result = Image.alpha_composite(result, img)
    return result


def apply_mask(img, mask):
    """Apply rounded rectangle mask."""
    result = img.copy()
    result.putalpha(mask)
    return result


# =============================================================================
# Style: Monochrome
# =============================================================================


def gen_monochrome(round_num, variant=0):
    """Generate monochrome icon variants."""
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))

    if variant == 0:
        # Pure white bg, black elements
        bg_color = (255, 255, 255, 255)
        fg_color = (30, 30, 30)
    elif variant == 1:
        # Pure black bg, white elements
        bg_color = (20, 20, 25, 255)
        fg_color = (240, 240, 240)
    elif variant == 2:
        # Warm grey bg, charcoal elements
        bg_color = (245, 242, 238, 255)
        fg_color = (60, 55, 50)
    elif variant == 3:
        # Dark charcoal bg, silver elements
        bg_color = (35, 35, 40, 255)
        fg_color = (200, 200, 205)
    elif variant == 4:
        # Mid grey bg, dark elements, high contrast
        bg_color = (180, 180, 185, 255)
        fg_color = (15, 15, 15)
    else:
        # Cool slate bg, off-white elements
        bg_color = (45, 50, 60, 255)
        fg_color = (230, 235, 240)

    draw = ImageDraw.Draw(img)
    draw.rounded_rectangle([0, 0, SIZE - 1, SIZE - 1], radius=CORNER_RADIUS, fill=bg_color)

    bracket_cy = SIZE * 0.38
    draw_code_brackets(draw, SIZE / 2, bracket_cy, SIZE * 0.32, int(SIZE * 0.045), fg_color)
    draw_bars(draw, SIZE / 2, SIZE * 0.68, SIZE * 0.42, SIZE * 0.038, SIZE * 0.035, 3, fg_color, radius=8)

    mask = rounded_rect_mask(SIZE, CORNER_RADIUS)
    return apply_mask(img, mask)


# =============================================================================
# Style: Neon Cyber
# =============================================================================


def gen_neon(round_num, color_scheme="purple", variant=0):
    """Generate neon cyberpunk icon variants."""
    schemes = {
        "purple": {
            "bg_center": (40, 10, 60),
            "bg_edge": (15, 5, 30),
            "primary": (200, 50, 255),
            "secondary": (140, 80, 255),
            "glow": (180, 50, 255),
            "accent": (255, 100, 220),
        },
        "green": {
            "bg_center": (10, 40, 35),
            "bg_edge": (5, 18, 15),
            "primary": (0, 255, 180),
            "secondary": (50, 220, 140),
            "glow": (0, 255, 160),
            "accent": (100, 255, 200),
        },
        "orange": {
            "bg_center": (50, 25, 5),
            "bg_edge": (25, 10, 2),
            "primary": (255, 160, 30),
            "secondary": (255, 120, 50),
            "glow": (255, 140, 20),
            "accent": (255, 200, 80),
        },
    }

    s = schemes[color_scheme]

    # Vary background and glow per variant
    if variant == 0:
        bg = make_radial_gradient(SIZE, s["bg_center"], s["bg_edge"])
        fg = s["primary"]
        glow_c = s["glow"]
        bar_color = s["secondary"]
        glow_radius = 25
    elif variant == 1:
        # Darker, more contrast, stronger glow
        darker_center = tuple(max(0, c - 15) for c in s["bg_center"])
        darker_edge = tuple(max(0, c - 10) for c in s["bg_edge"])
        bg = make_radial_gradient(SIZE, darker_center, darker_edge)
        fg = s["accent"]
        glow_c = s["primary"]
        bar_color = s["primary"]
        glow_radius = 30
    elif variant == 2:
        # Gradient background with subtle grid feel
        bg = make_gradient(SIZE, (*s["bg_edge"], 255), (*s["bg_center"], 255))
        fg = s["primary"]
        glow_c = s["accent"]
        bar_color = s["accent"]
        glow_radius = 20
    elif variant == 3:
        # Very dark, minimal glow, sleek
        bg = Image.new("RGBA", (SIZE, SIZE), (*tuple(max(0, c - 20) for c in s["bg_edge"]), 255))
        fg = s["primary"]
        glow_c = s["glow"]
        bar_color = s["secondary"]
        glow_radius = 15
    elif variant == 4:
        # Warm shifted, brighter center
        brighter = tuple(min(255, c + 20) for c in s["bg_center"])
        bg = make_radial_gradient(SIZE, brighter, s["bg_edge"], cx=0.5, cy=0.4)
        fg = s["accent"]
        glow_c = s["primary"]
        bar_color = s["accent"]
        glow_radius = 28
    else:
        # Diagonal gradient feel
        bg = make_gradient(SIZE, (*s["bg_center"], 255), (*s["bg_edge"], 255))
        fg = s["secondary"]
        glow_c = s["glow"]
        bar_color = s["primary"]
        glow_radius = 22

    # Apply rounded rect mask to background
    mask = rounded_rect_mask(SIZE, CORNER_RADIUS)
    bg = apply_mask(bg, mask)

    # Draw elements on transparent layer for glow
    elements = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(elements)

    bracket_cy = SIZE * 0.38
    draw_code_brackets(draw, SIZE / 2, bracket_cy, SIZE * 0.32, int(SIZE * 0.04), fg)
    draw_bars(draw, SIZE / 2, SIZE * 0.68, SIZE * 0.42, SIZE * 0.035, SIZE * 0.032, 3, bar_color, radius=6)

    # Add glow
    glowed = add_glow(elements, glow_c, radius=glow_radius, intensity=0.7)

    # Composite
    result = Image.alpha_composite(bg, glowed)
    return result


# =============================================================================
# Main: Generate all rounds
# =============================================================================


def generate_round(round_num):
    """Generate one round of all styles."""
    variant = (round_num - 1) % 6  # cycle through variants

    results = {}

    # Monochrome (cycle through light/dark variants)
    mono = gen_monochrome(round_num, variant=variant)
    path = OUT_DIR / "monochrome" / "rounds" / f"round_{round_num:02d}_v{variant}.png"
    mono.save(str(path), "PNG")
    results["monochrome"] = path
    print(f"  Monochrome v{variant} → {path.name}")

    # Neon variants
    for color in ["purple", "green", "orange"]:
        neon = gen_neon(round_num, color_scheme=color, variant=variant)
        path = OUT_DIR / f"neon-{color}" / "rounds" / f"round_{round_num:02d}_v{variant}.png"
        neon.save(str(path), "PNG")
        results[f"neon-{color}"] = path
        print(f"  Neon {color} v{variant} → {path.name}")

    return results


def main():
    rounds = int(sys.argv[1]) if len(sys.argv) > 1 else 10
    print(f"Generating {rounds} rounds of icons...\n")

    for r in range(1, rounds + 1):
        print(f"Round {r}/{rounds}:")
        generate_round(r)
        print()

    print("Done! Review results in each style's rounds/ folder.")


if __name__ == "__main__":
    main()
