#!/usr/bin/env python3
"""Generate utilization chart variant screenshots using Pillow.

Since we can't run SwiftUI previews from CLI, this generates visual
mockups of each chart variant for comparison.
"""

import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

random.seed(42)

SIZE_W = 390 * 2  # @2x
SIZE_H = 240 * 2
BAR_AREA_Y = 60 * 2
BAR_AREA_H = 140 * 2
PADDING = 32
OUT = Path(__file__).parent

TINT = (209, 140, 71)  # Claude color
TINT2 = (128, 90, 213)  # Codex purple
TINT3 = (60, 130, 230)  # Cursor blue
BG = (28, 28, 30)
TRACK = (50, 50, 52)


def sample_data(n=40):
    return [random.uniform(10, 95) for _ in range(n)]


def draw_label(draw, text, x, y, color=(180, 180, 180)):
    draw.text((x, y), text, fill=color)


def save(img, name, subdir="provider"):
    path = OUT / subdir / f"{name}.png"
    img.save(str(path), "PNG")
    print(f"  {path.name}")


# ============ PROVIDER VARIANTS ============

def p1_mac_replica(data):
    img = Image.new("RGBA", (SIZE_W, SIZE_H), BG)
    draw = ImageDraw.Draw(img)
    draw_label(draw, "1. Mac Replica (track + fill)", PADDING, 20, (200, 200, 200))
    n = len(data)
    bw = 10
    gap = 4
    for i, v in enumerate(data):
        x = PADDING + i * (bw + gap)
        # Track
        draw.rectangle([x, BAR_AREA_Y, x + bw, BAR_AREA_Y + BAR_AREA_H], fill=TRACK)
        # Fill
        h = int(BAR_AREA_H * v / 100)
        draw.rectangle([x, BAR_AREA_Y + BAR_AREA_H - h, x + bw, BAR_AREA_Y + BAR_AREA_H], fill=TINT)
    draw_label(draw, "40 points  |  Avg 52%", PADDING, BAR_AREA_Y + BAR_AREA_H + 16)
    save(img, "v1_mac_replica")


def p2_gradient(data):
    img = Image.new("RGBA", (SIZE_W, SIZE_H), BG)
    draw = ImageDraw.Draw(img)
    draw_label(draw, "2. Gradient Fill", PADDING, 20, (200, 200, 200))
    bw = 12
    gap = 3
    for i, v in enumerate(data):
        x = PADDING + i * (bw + gap)
        h = int(BAR_AREA_H * v / 100)
        y_top = BAR_AREA_Y + BAR_AREA_H - h
        for dy in range(h):
            t = dy / max(h, 1)
            r = int(TINT[0] * (0.4 + 0.6 * t))
            g = int(TINT[1] * (0.4 + 0.6 * t))
            b = int(TINT[2] * (0.4 + 0.6 * t))
            draw.rectangle([x, y_top + dy, x + bw, y_top + dy + 1], fill=(r, g, b))
    save(img, "v2_gradient")


def p3_area_line(data):
    img = Image.new("RGBA", (SIZE_W, SIZE_H), BG)
    draw = ImageDraw.Draw(img)
    draw_label(draw, "3. Area Line", PADDING, 20, (200, 200, 200))
    gap = 14
    points = []
    for i, v in enumerate(data):
        x = PADDING + i * gap
        y = BAR_AREA_Y + BAR_AREA_H - int(BAR_AREA_H * v / 100)
        points.append((x, y))
    # Area
    if len(points) > 1:
        area_pts = list(points) + [(points[-1][0], BAR_AREA_Y + BAR_AREA_H), (points[0][0], BAR_AREA_Y + BAR_AREA_H)]
        draw.polygon(area_pts, fill=(*TINT, 40))
        draw.line(points, fill=TINT, width=3)
    save(img, "v3_area_line")


def p4_capsule(data):
    img = Image.new("RGBA", (SIZE_W, SIZE_H), BG)
    draw = ImageDraw.Draw(img)
    draw_label(draw, "4. Capsule Bar", PADDING, 20, (200, 200, 200))
    bw = 16
    gap = 6
    for i, v in enumerate(data):
        x = PADDING + i * (bw + gap)
        draw.rounded_rectangle([x, BAR_AREA_Y, x + bw, BAR_AREA_Y + BAR_AREA_H], radius=8, fill=TRACK)
        h = int(BAR_AREA_H * v / 100)
        draw.rounded_rectangle([x, BAR_AREA_Y + BAR_AREA_H - h, x + bw, BAR_AREA_Y + BAR_AREA_H], radius=8, fill=TINT)
    save(img, "v4_capsule")


def p5_signal(data):
    img = Image.new("RGBA", (SIZE_W, SIZE_H), BG)
    draw = ImageDraw.Draw(img)
    draw_label(draw, "5. Signal Waveform", PADDING, 20, (200, 200, 200))
    bw = 4
    gap = 2
    for i, v in enumerate(data):
        x = PADDING + i * (bw + gap)
        h = int(BAR_AREA_H * v / 100)
        draw.rectangle([x, BAR_AREA_Y + BAR_AREA_H - h, x + bw, BAR_AREA_Y + BAR_AREA_H], fill=TINT)
    save(img, "v5_signal")


def p6_heat(data):
    img = Image.new("RGBA", (SIZE_W, SIZE_H), BG)
    draw = ImageDraw.Draw(img)
    draw_label(draw, "6. Heat Color Scale", PADDING, 20, (200, 200, 200))
    bw = 10
    gap = 4
    for i, v in enumerate(data):
        x = PADDING + i * (bw + gap)
        h = int(BAR_AREA_H * v / 100)
        if v >= 80: c = (220, 50, 50)
        elif v >= 60: c = (220, 140, 50)
        elif v >= 40: c = (200, 200, 60)
        else: c = (60, 180, 80)
        draw.rectangle([x, BAR_AREA_Y + BAR_AREA_H - h, x + bw, BAR_AREA_Y + BAR_AREA_H], fill=c)
    save(img, "v6_heat")


def p7_dots(data):
    img = Image.new("RGBA", (SIZE_W, SIZE_H), BG)
    draw = ImageDraw.Draw(img)
    draw_label(draw, "7. Dot Matrix", PADDING, 20, (200, 200, 200))
    gap = 14
    for i, v in enumerate(data):
        x = PADDING + i * gap
        y = BAR_AREA_Y + BAR_AREA_H - int(BAR_AREA_H * v / 100)
        r = max(3, int(v / 10))
        draw.ellipse([x - r, y - r, x + r, y + r], fill=TINT)
    save(img, "v7_dots")


def p8_step(data):
    img = Image.new("RGBA", (SIZE_W, SIZE_H), BG)
    draw = ImageDraw.Draw(img)
    draw_label(draw, "8. Step Line", PADDING, 20, (200, 200, 200))
    gap = 14
    points = []
    for i, v in enumerate(data):
        x = PADDING + i * gap
        y = BAR_AREA_Y + BAR_AREA_H - int(BAR_AREA_H * v / 100)
        if points:
            points.append((x, points[-1][1]))
        points.append((x, y))
    if len(points) > 1:
        area_pts = list(points) + [(points[-1][0], BAR_AREA_Y + BAR_AREA_H), (points[0][0], BAR_AREA_Y + BAR_AREA_H)]
        draw.polygon(area_pts, fill=(*TINT, 25))
        draw.line(points, fill=TINT, width=2)
    save(img, "v8_step")


def p9_dual(data):
    img = Image.new("RGBA", (SIZE_W, SIZE_H), BG)
    draw = ImageDraw.Draw(img)
    draw_label(draw, "9. Dual Color (Used + Remaining)", PADDING, 20, (200, 200, 200))
    bw = 10
    gap = 4
    for i, v in enumerate(data):
        x = PADDING + i * (bw + gap)
        h = int(BAR_AREA_H * v / 100)
        # Remaining (gray)
        draw.rectangle([x, BAR_AREA_Y, x + bw, BAR_AREA_Y + BAR_AREA_H - h], fill=(80, 80, 85))
        # Used (tint)
        draw.rectangle([x, BAR_AREA_Y + BAR_AREA_H - h, x + bw, BAR_AREA_Y + BAR_AREA_H], fill=TINT)
    save(img, "v9_dual")


def p10_spark(data):
    img = Image.new("RGBA", (SIZE_W, SIZE_H // 2), BG)
    draw = ImageDraw.Draw(img)
    draw_label(draw, "10. Mini Spark", PADDING, 10, (200, 200, 200))
    bw = 6
    gap = 2
    spark_h = 60 * 2
    for i, v in enumerate(data):
        x = PADDING + i * (bw + gap)
        h = int(spark_h * v / 100)
        draw.rectangle([x, 50 + spark_h - h, x + bw, 50 + spark_h], fill=TINT)
    avg = sum(data) / len(data)
    draw_label(draw, f"{avg:.0f}% avg", PADDING + len(data) * (bw + gap) + 20, 60, TINT)
    save(img, "v10_spark")


# ============ COST AGGREGATE VARIANTS ============

def c1_stacked(data_a, data_b, data_c):
    img = Image.new("RGBA", (SIZE_W, SIZE_H), BG)
    draw = ImageDraw.Draw(img)
    draw_label(draw, "1. Stacked Bar", PADDING, 20, (200, 200, 200))
    bw = 14
    gap = 4
    for i in range(len(data_a)):
        x = PADDING + i * (bw + gap)
        total_h = BAR_AREA_H
        ha = int(total_h * data_a[i] / 300)
        hb = int(total_h * data_b[i] / 300)
        hc = int(total_h * data_c[i] / 300)
        y = BAR_AREA_Y + total_h
        draw.rectangle([x, y - ha, x + bw, y], fill=TINT)
        y -= ha
        draw.rectangle([x, y - hb, x + bw, y], fill=TINT2)
        y -= hb
        draw.rectangle([x, y - hc, x + bw, y], fill=TINT3)
    save(img, "c1_stacked", "cost-aggregate")


def c5_ring(data_a, data_b, data_c):
    img = Image.new("RGBA", (SIZE_W, SIZE_H), BG)
    draw = ImageDraw.Draw(img)
    draw_label(draw, "5. Ring Gauge", PADDING, 20, (200, 200, 200))
    cx, cy = SIZE_W // 3, SIZE_H // 2
    avgs = [sum(d) / len(d) for d in [data_a, data_b, data_c]]
    colors = [TINT, TINT2, TINT3]
    names = ["Claude", "Codex", "Cursor"]
    for idx, (avg, c) in enumerate(zip(avgs, colors)):
        r = 90 - idx * 24
        extent = int(360 * avg / 100)
        draw.arc([cx - r, cy - r, cx + r, cy + r], -90, -90 + extent, fill=c, width=14)
        draw.arc([cx - r, cy - r, cx + r, cy + r], -90 + extent, 270, fill=(*c, 40), width=14)
    for idx, (avg, c, name) in enumerate(zip(avgs, colors, names)):
        y = BAR_AREA_Y + idx * 40
        draw.ellipse([SIZE_W // 2 + 40, y, SIZE_W // 2 + 52, y + 12], fill=c)
        draw_label(draw, f"{name}: {avg:.0f}%", SIZE_W // 2 + 60, y - 2)
    save(img, "c5_ring", "cost-aggregate")


def c10_dashboard(data_a, data_b, data_c):
    img = Image.new("RGBA", (SIZE_W, SIZE_H), BG)
    draw = ImageDraw.Draw(img)
    draw_label(draw, "10. Dashboard Summary", PADDING, 20, (200, 200, 200))
    avgs = [sum(d) / len(d) for d in [data_a, data_b, data_c]]
    total = sum(avgs) / 300 * 100
    draw_label(draw, f"{total:.0f}%", PADDING + 20, SIZE_H // 2 - 40, TINT)
    draw_label(draw, "Overall", PADDING + 20, SIZE_H // 2 + 20, (120, 120, 120))
    # Mini stacked bars
    bw = 8
    gap = 3
    for i in range(len(data_a)):
        x = PADDING + 160 + i * (bw + gap)
        total_h = BAR_AREA_H
        ha = int(total_h * data_a[i] / 300)
        hb = int(total_h * data_b[i] / 300)
        hc = int(total_h * data_c[i] / 300)
        y = BAR_AREA_Y + total_h
        draw.rectangle([x, y - ha, x + bw, y], fill=TINT)
        y -= ha
        draw.rectangle([x, y - hb, x + bw, y], fill=TINT2)
        y -= hb
        draw.rectangle([x, y - hc, x + bw, y], fill=TINT3)
    save(img, "c10_dashboard", "cost-aggregate")


def main():
    data = sample_data(40)
    data_a = sample_data(20)
    data_b = sample_data(20)
    data_c = sample_data(20)

    print("Provider variants:")
    p1_mac_replica(data)
    p2_gradient(data)
    p3_area_line(data)
    p4_capsule(data)
    p5_signal(data)
    p6_heat(data)
    p7_dots(data)
    p8_step(data)
    p9_dual(data)
    p10_spark(data)

    print("\nCost aggregate variants:")
    c1_stacked(data_a, data_b, data_c)
    c5_ring(data_a, data_b, data_c)
    c10_dashboard(data_a, data_b, data_c)

    print("\nDone. All mockups saved.")


if __name__ == "__main__":
    main()
