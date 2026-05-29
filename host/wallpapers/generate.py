#!/usr/bin/env python3
"""Generate the Catppuccin Mocha wallpaper used by the headless Sway desktop.

Dependency-free (stdlib only: zlib + struct + math + random) so it runs anywhere
Python 3 is available — no ImageMagick / PIL needed.

Default style is a scenic "mountains" scene: a soft dusk-gradient sky with a
glowing mauve moon and several layered ridge silhouettes in Catppuccin Mocha
tones. It is fully static, so it costs nothing on the VNC stream after the first
frame, and being smooth/low-contrast it compresses to a small PNG.

Usage:
    python3 generate.py                       # mountains -> mocha.png (1920x1080)
    python3 generate.py OUT.png W H [style]   # style: mountains | gradient
"""
import math
import os
import random
import struct
import sys
import zlib

# --- Catppuccin Mocha ---------------------------------------------------------
CRUST = (0x11, 0x11, 0x1b)
MANTLE = (0x18, 0x18, 0x25)
BASE = (0x1e, 0x1e, 0x2e)
SURFACE0 = (0x31, 0x32, 0x44)
SURFACE1 = (0x45, 0x47, 0x5a)
OVERLAY0 = (0x6c, 0x70, 0x86)
MAUVE = (0xcb, 0xa6, 0xf7)
BLUE = (0x89, 0xb4, 0xfa)
LAVENDER = (0xb4, 0xbe, 0xfe)


def lerp(a, b, t):
    return a + (b - a) * t


def mix(c1, c2, t):
    t = 0.0 if t < 0 else 1.0 if t > 1 else t
    return tuple(lerp(c1[i], c2[i], t) for i in range(3))


def clamp8(c):
    return tuple(0 if v < 0 else 255 if v > 255 else int(round(v)) for v in c)


# --- ridge silhouette ---------------------------------------------------------
def ridge_heights(width, base_y, amp, seed):
    """A smooth ridge line (y per column) from a few summed sines."""
    rng = random.Random(seed)
    waves = []
    for freq, weight in ((1.3, 0.55), (2.7, 0.28), (5.1, 0.12), (9.3, 0.05)):
        waves.append((freq, weight, rng.uniform(0, 2 * math.pi)))
    heights = []
    for x in range(width):
        t = x / width
        v = sum(w * math.sin(2 * math.pi * f * t + p) for f, w, p in waves)
        heights.append(base_y + amp * v)
    return heights


def render_mountains(width, height):
    # sky stops (top -> bottom): crust -> mantle -> base, warm mauve near horizon
    def sky(y):
        t = y / height
        if t < 0.45:
            col = mix(CRUST, MANTLE, t / 0.45)
        elif t < 0.72:
            col = mix(MANTLE, BASE, (t - 0.45) / 0.27)
        else:
            col = mix(BASE, mix(BASE, MAUVE, 0.10), (t - 0.72) / 0.28)
        return col

    # glowing moon, upper area
    mx, my = width * 0.74, height * 0.26
    moon_r = height * 0.085
    glow_r = height * 0.42

    # ridge layers, back (lighter/higher) -> front (darker/lower)
    layers = [
        (mix(SURFACE1, LAVENDER, 0.25), 0.56, 0.05, 11),
        (mix(SURFACE0, BLUE, 0.10), 0.66, 0.07, 23),
        (mix(MANTLE, SURFACE0, 0.55), 0.75, 0.085, 37),
        (CRUST, 0.84, 0.10, 51),
    ]
    layer_h = []
    for _, by, amp, seed in layers:
        layer_h.append(ridge_heights(width, by * height, amp * height, seed))

    raw = bytearray()
    for y in range(height):
        raw.append(0)  # PNG filter type 0 (None)
        for x in range(width):
            col = sky(y)
            # moon glow + disc
            d = math.hypot(x - mx, y - my)
            if d < glow_r:
                col = mix(col, MAUVE, (1.0 - d / glow_r) ** 3 * 0.22)
            if d < moon_r:
                col = mix(mix(LAVENDER, MAUVE, 0.3), (0xff, 0xff, 0xff), 0.15)
            # mountains: first (front-most) layer whose ridge is above this pixel
            for li in range(len(layers) - 1, -1, -1):
                if y >= layer_h[li][x]:
                    col = layers[li][0]
                    break
            raw.extend(clamp8(col))
    return bytes(raw)


def render_gradient(width, height):
    """Original subtle diagonal gradient (kept as a lightweight fallback)."""
    raw = bytearray()
    diag = width + height
    gx, gy = width * 0.12, height * 0.10
    glow_r = max(width, height) * 0.55
    for y in range(height):
        raw.append(0)
        for x in range(width):
            d = (x + y) / diag
            col = mix(BASE, MANTLE, d / 0.5) if d < 0.5 \
                else mix(MANTLE, CRUST, (d - 0.5) / 0.5)
            dist = math.hypot(x - gx, y - gy)
            glow = max(0.0, 1.0 - dist / glow_r) ** 2 * 0.10
            raw.extend(clamp8(mix(col, MAUVE, glow)))
    return bytes(raw)


def write_png(path, width, height, raw):
    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff))

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)  # 8-bit RGB
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", ihdr))
        f.write(chunk(b"IDAT", zlib.compress(raw, 9)))
        f.write(chunk(b"IEND", b""))


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, "mocha.png")
    width = int(sys.argv[2]) if len(sys.argv) > 2 else 1920
    height = int(sys.argv[3]) if len(sys.argv) > 3 else 1080
    style = sys.argv[4] if len(sys.argv) > 4 else "mountains"
    raw = render_gradient(width, height) if style == "gradient" \
        else render_mountains(width, height)
    write_png(out, width, height, raw)
    print(f"wrote {out} ({width}x{height}, style={style})")


if __name__ == "__main__":
    main()
