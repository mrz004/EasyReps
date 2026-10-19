"""Generate the Easy Reps logo and all app icon sizes.

The mark is a dumbbell inside a circular "repeat" arrow (reps): a Fog dumbbell
and a light Aloe arrow on a Slate Blue tile with a soft glass highlight, using
the app palette (Slate Blue, Fog, Aloe, Charcoal).

Usage (from the repository root):
  python tools/make_icons.py

Outputs:
  assets/branding/logo.png              in-app logo (rounded tile, 512 px)
  assets/branding/play_store_512.png    full-bleed square for the Play Store
  android/app/src/main/res/mipmap-*/ic_launcher*.png    legacy + adaptive layers
  android/app/src/main/res/drawable-xxxhdpi/splash_logo.png
"""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / "android" / "app" / "src" / "main" / "res"
BRANDING = ROOT / "assets" / "branding"

SUPERSAMPLE = 4
SLATE_LIGHT = (76, 98, 112)   # lighter Slate Blue, top left
SLATE_DARK = (44, 58, 67)     # deeper Slate Blue, bottom right
FOG = (226, 222, 206, 255)    # #E2DECE
ALOE_LIGHT = (183, 190, 152, 255)  # light Aloe for the arrow
WHITE = (255, 255, 255, 255)

DENSITIES = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}


def gradient_background(size: int) -> Image.Image:
    """Diagonal Slate Blue shading with a soft glass highlight at the top left."""
    # Diagonal ramp = (horizontal + vertical) / 2: 0 at top left, 255 at bottom right.
    vertical = Image.linear_gradient("L")
    horizontal = vertical.transpose(Image.Transpose.ROTATE_90)
    ramp = ImageChops.add(horizontal, vertical, scale=2.0).resize((size, size), Image.LANCZOS)
    base = Image.composite(
        Image.new("RGB", (size, size), SLATE_DARK),
        Image.new("RGB", (size, size), SLATE_LIGHT),
        ramp,
    ).convert("RGBA")
    # radial_gradient is 0 at the centre; fade to 0 well inside the box edge so
    # no square outline shows.
    glow = Image.radial_gradient("L").point(lambda v: int(max(0.0, 1 - v / 160) * 255 * 0.18))
    glow = glow.resize((size, size), Image.LANCZOS)
    highlight = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    highlight.putalpha(glow)
    offset = int(-size * 0.28)
    base.alpha_composite(highlight, (offset, offset))
    return base




def mark(size: int, scale: float = 1.0, color=FOG, arrow_color=ALOE_LIGHT) -> Image.Image:
    """Dumbbell inside a circular repeat arrow, on transparency."""
    s = size * SUPERSAMPLE
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = s / 2
    u = s * scale  # design unit: fractions of the canvas

    # Repeat arrow: arc from ~3 o'clock clockwise round to ~12:40.
    radius, stroke = 0.27 * u, 0.062 * u
    start, end = -8, 288
    outer = radius + stroke / 2
    d.arc((c - outer, c - outer, c + outer, c + outer), start, end, fill=arrow_color, width=round(stroke))
    sx, sy = _on_circle(c, radius, start)
    d.ellipse((sx - stroke / 2, sy - stroke / 2, sx + stroke / 2, sy + stroke / 2), fill=arrow_color)

    # Arrowhead at the end of the arc, pointing clockwise.
    theta = math.radians(end)
    px, py = _on_circle(c, radius, end)
    tangent = (-math.sin(theta), math.cos(theta))
    normal = (math.cos(theta), math.sin(theta))
    head_len, head_half = 0.10 * u, 0.085 * u
    tip = (px + tangent[0] * head_len, py + tangent[1] * head_len)
    back = (px - tangent[0] * 0.012 * u, py - tangent[1] * 0.012 * u)
    d.polygon(
        [
            tip,
            (back[0] + normal[0] * head_half, back[1] + normal[1] * head_half),
            (back[0] - normal[0] * head_half, back[1] - normal[1] * head_half),
        ],
        fill=arrow_color,
    )

    # Dumbbell: bar, two inner plates, two outer plates.
    def rect(cx: float, w: float, h: float) -> None:
        r = min(w, h) * 0.38
        d.rounded_rectangle((c + cx - w / 2, c - h / 2, c + cx + w / 2, c + h / 2), r, fill=color)

    rect(0, 0.34 * u, 0.040 * u)
    for side in (-1, 1):
        rect(side * 0.112 * u, 0.050 * u, 0.215 * u)
        rect(side * 0.160 * u, 0.038 * u, 0.140 * u)

    return img.resize((size, size), Image.LANCZOS)


def _on_circle(c: float, r: float, degrees: float) -> tuple[float, float]:
    t = math.radians(degrees)
    return c + r * math.cos(t), c + r * math.sin(t)


def rounded_tile(size: int, radius_frac: float = 0.225, margin_frac: float = 0.0) -> Image.Image:
    """Gradient tile with rounded corners and the mark, transparent outside."""
    margin = round(size * margin_frac)
    inner = size - 2 * margin
    tile = gradient_background(inner)
    tile.alpha_composite(mark(inner))
    mask = Image.new("L", (inner * SUPERSAMPLE,) * 2, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, inner * SUPERSAMPLE - 1, inner * SUPERSAMPLE - 1),
        radius=inner * SUPERSAMPLE * radius_frac,
        fill=255,
    )
    tile.putalpha(ImageChops.multiply(tile.getchannel("A"), mask.resize((inner, inner), Image.LANCZOS)))
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.alpha_composite(tile, (margin, margin))
    return out


def save(img: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, optimize=True)
    print(f"  {path.relative_to(ROOT)}  {img.size[0]}px")


def main() -> None:
    print("Branding:")
    save(rounded_tile(512), BRANDING / "logo.png")
    play = gradient_background(512)
    play.alpha_composite(mark(512))
    save(play.convert("RGB"), BRANDING / "play_store_512.png")

    print("Android launcher icons:")
    for name, k in DENSITIES.items():
        legacy, adaptive = round(48 * k), round(108 * k)
        folder = RES / f"mipmap-{name}"
        save(rounded_tile(legacy, margin_frac=1 / 24), folder / "ic_launcher.png")
        # Adaptive layers: the mark must fit the 66 dp safe circle of 108 dp.
        save(gradient_background(adaptive), folder / "ic_launcher_background.png")
        save(mark(adaptive, scale=0.92), folder / "ic_launcher_foreground.png")
        # Monochrome (Android 13 themed icons): one colour, the system tints it.
        save(mark(adaptive, scale=0.92, color=WHITE, arrow_color=WHITE), folder / "ic_launcher_monochrome.png")

    print("Splash:")
    save(rounded_tile(384), RES / "drawable-xxxhdpi" / "splash_logo.png")


if __name__ == "__main__":
    main()
