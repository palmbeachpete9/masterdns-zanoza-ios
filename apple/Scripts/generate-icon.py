#!/usr/bin/env python3
"""Generate the Zanoza iOS AppIcon set.

Renders a 1024x1024 master icon with:
  - warm orange radial-ish gradient background
  - large semi-transparent white hot-air balloon silhouette
  - simplified world-map dot pattern etched on top of the balloon (clipped)
  - a tiny basket below the balloon for character

Then downsizes to every iOS AppIcon slot found in
Sources/ZanozaApp/Assets.xcassets/AppIcon.appiconset/Contents.json.
"""

from __future__ import annotations

import json
import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

HERE = Path(__file__).resolve().parent
APPICON_DIR = (HERE / "../Sources/ZanozaApp/Assets.xcassets/AppIcon.appiconset").resolve()

MASTER = 1024


def make_gradient_background(size: int) -> Image.Image:
    """Warm orange radial gradient (top-left light, bottom-right deep)."""
    top = (255, 180, 90)
    bottom = (228, 92, 30)
    img = Image.new("RGB", (size, size), bottom)
    pixels = img.load()
    diag = math.hypot(size, size)
    cx, cy = size * 0.32, size * 0.22
    for y in range(size):
        for x in range(size):
            d = math.hypot(x - cx, y - cy) / diag
            t = max(0.0, min(1.0, d * 1.35))
            r = int(top[0] * (1 - t) + bottom[0] * t)
            g = int(top[1] * (1 - t) + bottom[1] * t)
            b = int(top[2] * (1 - t) + bottom[2] * t)
            pixels[x, y] = (r, g, b)
    return img


# Tiny equirectangular landmass mask (1 = land, 0 = water).
# Each row is a string; '.' = water, '#' = land. 24x12 cells covers globally
# recognisable shapes when rendered as dots.
WORLD_MAP = [
    "........................",
    "......#####.#####.......",
    "....#######.##########..",
    "...##############.####..",
    "....#####...#######.....",
    ".....##......######.....",
    ".......#.....#####......",
    ".......#......####......",
    "........#.....###..#....",
    "........#......##.#.....",
    ".........#......##......",
    "..........#....##.......",
]


def make_balloon_layer(size: int) -> Image.Image:
    """Balloon silhouette (semi-transparent white) with map dots and basket."""
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer, "RGBA")

    cx = size / 2
    cy = size * 0.46
    balloon_r = size * 0.32

    # Balloon body is translucent white (~70 % alpha). Map dots are nearly
    # opaque white so they read as "etched" against the softer balloon.
    body_alpha = 180
    body = (255, 255, 255, body_alpha)

    # Balloon body (slightly squashed sphere).
    draw.ellipse(
        (
            cx - balloon_r,
            cy - balloon_r * 1.05,
            cx + balloon_r,
            cy + balloon_r * 0.95,
        ),
        fill=body,
    )

    # Bottom "neck" trapezoid that meets the basket.
    neck_top_w = balloon_r * 0.55
    neck_bot_w = balloon_r * 0.30
    neck_top_y = cy + balloon_r * 0.85
    neck_bot_y = cy + balloon_r * 1.20
    draw.polygon(
        [
            (cx - neck_top_w, neck_top_y),
            (cx + neck_top_w, neck_top_y),
            (cx + neck_bot_w, neck_bot_y),
            (cx - neck_bot_w, neck_bot_y),
        ],
        fill=body,
    )

    # Map dots, clipped to the balloon body.
    balloon_mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(balloon_mask).ellipse(
        (
            cx - balloon_r,
            cy - balloon_r * 1.05,
            cx + balloon_r,
            cy + balloon_r * 0.95,
        ),
        fill=255,
    )

    dots_layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    dots_draw = ImageDraw.Draw(dots_layer, "RGBA")
    rows = len(WORLD_MAP)
    cols = len(WORLD_MAP[0])
    pad = balloon_r * 0.10
    grid_w = (balloon_r - pad) * 2
    grid_h = grid_w * (rows / cols) * 0.95
    grid_x0 = cx - grid_w / 2
    grid_y0 = cy - grid_h / 2
    dot = max(2, int(size * 0.012))
    # Brighter, more-opaque white than the balloon body so the map "etches".
    dot_color = (255, 255, 255, 245)
    for ry, row in enumerate(WORLD_MAP):
        for rx, ch in enumerate(row):
            if ch != "#":
                continue
            px = grid_x0 + (rx + 0.5) * (grid_w / cols)
            py = grid_y0 + (ry + 0.5) * (grid_h / rows)
            dots_draw.ellipse(
                (px - dot, py - dot, px + dot, py + dot),
                fill=dot_color,
            )

    # Clip dots into the balloon body.
    dots_layer.putalpha(
        Image.eval(
            Image.composite(
                dots_layer.split()[3],
                Image.new("L", (size, size), 0),
                balloon_mask,
            ),
            lambda v: v,
        )
    )

    layer = Image.alpha_composite(layer, dots_layer)

    # Basket: small rounded rectangle suspended below the neck.
    basket_w = balloon_r * 0.55
    basket_h = balloon_r * 0.22
    basket_x0 = cx - basket_w / 2
    basket_x1 = cx + basket_w / 2
    basket_y0 = neck_bot_y + balloon_r * 0.10
    basket_y1 = basket_y0 + basket_h
    basket = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(basket).rounded_rectangle(
        (basket_x0, basket_y0, basket_x1, basket_y1),
        radius=int(basket_h * 0.30),
        fill=(255, 255, 255, body_alpha),
    )
    layer = Image.alpha_composite(layer, basket)

    # Suspension cords from balloon to basket corners.
    cord_layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    cord_draw = ImageDraw.Draw(cord_layer, "RGBA")
    cord = (255, 255, 255, body_alpha)
    cord_w = max(2, int(size * 0.006))
    cord_draw.line(
        [(cx - neck_bot_w, neck_bot_y), (basket_x0 + basket_w * 0.10, basket_y0)],
        fill=cord, width=cord_w,
    )
    cord_draw.line(
        [(cx + neck_bot_w, neck_bot_y), (basket_x1 - basket_w * 0.10, basket_y0)],
        fill=cord, width=cord_w,
    )
    layer = Image.alpha_composite(layer, cord_layer)

    # Subtle inner highlight on the balloon's upper-left to add depth.
    highlight = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    hi_draw = ImageDraw.Draw(highlight, "RGBA")
    hi_r = balloon_r * 0.55
    hi_cx = cx - balloon_r * 0.25
    hi_cy = cy - balloon_r * 0.35
    hi_draw.ellipse(
        (hi_cx - hi_r, hi_cy - hi_r, hi_cx + hi_r, hi_cy + hi_r),
        fill=(255, 255, 255, 70),
    )
    highlight = highlight.filter(ImageFilter.GaussianBlur(size * 0.04))
    # Clip highlight to balloon body.
    masked = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    masked.paste(highlight, mask=balloon_mask)
    layer = Image.alpha_composite(layer, masked)

    return layer


def render_master() -> Image.Image:
    bg = make_gradient_background(MASTER).convert("RGBA")
    balloon = make_balloon_layer(MASTER)
    return Image.alpha_composite(bg, balloon)


def render_all():
    contents_path = APPICON_DIR / "Contents.json"
    with contents_path.open() as f:
        manifest = json.load(f)

    master = render_master()
    # Pre-rasterize once at maximum quality.
    for image in manifest["images"]:
        filename = image.get("filename")
        if not filename:
            continue
        size_str = image["size"]  # e.g. "60x60" or "83.5x83.5"
        scale = int(image["scale"].rstrip("x"))
        side = float(size_str.split("x")[0])
        pixel_side = int(round(side * scale))
        resized = master.resize((pixel_side, pixel_side), Image.LANCZOS)
        # iOS marketing icon must be RGB (no alpha). All others can be RGB too.
        out = resized.convert("RGB")
        out_path = APPICON_DIR / filename
        out.save(out_path, format="PNG", optimize=True)
        print(f"wrote {out_path.name}  ({pixel_side}x{pixel_side})")


if __name__ == "__main__":
    render_all()
