"""Renders the TrackpadTool app icon (Liquid Glass style) and writes
Resources/AppIcon.icns plus a 1024 px preview PNG.

Usage: python3 tools/make_icon.py <output-dir>
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

S = 2048                      # draw at 2x, downsample to 1024 at the end
BODY = int(S * 824 / 1024)    # macOS icon grid: 824 pt body on a 1024 canvas
OFF = (S - BODY) // 2


def hex_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def superellipse_mask(size, n=5.0):
    """Continuous-corner squircle like Apple's icon shape."""
    a = (size - 1) / 2
    y, x = np.mgrid[0:size, 0:size]
    v = np.abs((x - a) / a) ** n + np.abs((y - a) / a) ** n
    # soft edge for anti-aliasing
    alpha = np.clip((1.0 - v) * size / 6, 0, 1)
    return Image.fromarray((alpha * 255).astype(np.uint8), "L")


def gradient(size, stops, angle_xy=(0.45, 0.9)):
    w, h = size
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    t = (x / w) * angle_xy[0] + (y / h) * angle_xy[1]
    t = (t - t.min()) / (t.max() - t.min())
    out = np.zeros((h, w, 3), np.float32)
    pos = [p for p, _ in stops]
    cols = [np.array(hex_rgb(c), np.float32) for _, c in stops]
    for ch in range(3):
        out[..., ch] = np.interp(t, pos, [c[ch] for c in cols])
    return Image.fromarray(out.astype(np.uint8), "RGB").convert("RGBA")


def vertical_ramp(size, top, bottom):
    w, h = size
    ramp = np.linspace(top, bottom, h, dtype=np.float32)[:, None].repeat(w, 1)
    return Image.fromarray((np.clip(ramp, 0, 1) * 255).astype(np.uint8), "L")


def mul_masks(a, b):
    return Image.fromarray(
        (np.asarray(a, np.float32) * np.asarray(b, np.float32) / 255).astype(np.uint8), "L")


def blob(canvas, center, radius, color, alpha, blur):
    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    cx, cy = center
    d.ellipse([cx - radius, cy - radius, cx + radius, cy + radius],
              fill=hex_rgb(color) + (int(255 * alpha),))
    return Image.alpha_composite(canvas, layer.filter(ImageFilter.GaussianBlur(blur)))


def rounded_mask(size, box, radius):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle(box, radius=radius, fill=255)
    return m


def ring(mask, width):
    inner = mask.filter(ImageFilter.MinFilter(width * 2 + 1))
    return Image.fromarray(
        np.clip(np.asarray(mask, np.int16) - np.asarray(inner, np.int16), 0, 255).astype(np.uint8), "L")


def main(out_dir):
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)

    canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    # Apple's icon outline: straight sides with continuous corners (radius ≈ 22.5% of the body)
    body_mask = rounded_mask((S, S), [OFF, OFF, OFF + BODY, OFF + BODY], int(BODY * 0.225))
    body_mask = body_mask.filter(ImageFilter.GaussianBlur(1.2))

    # --- shadow under the body
    shadow = Image.new("RGBA", (S, S), (10, 14, 40, 0))
    shadow.putalpha(body_mask.point(lambda v: int(v * 0.45)))
    shadow = shadow.transform(shadow.size, Image.AFFINE, (1, 0, 0, 0, 1, -36))
    canvas = Image.alpha_composite(canvas, shadow.filter(ImageFilter.GaussianBlur(40)))

    # --- body: deep blue → indigo → violet, with liquid colour blobs
    body = gradient((S, S), [(0.0, "#46B4FF"), (0.45, "#3A5CF2"), (1.0, "#7A35E0")])
    body = blob(body, (int(S * 0.78), int(S * 0.80)), int(S * 0.30), "#FF5FCF", 0.55, 160)
    body = blob(body, (int(S * 0.22), int(S * 0.18)), int(S * 0.26), "#6FF3FF", 0.50, 150)
    body = blob(body, (int(S * 0.30), int(S * 0.85)), int(S * 0.18), "#5B2BE0", 0.45, 140)
    body.putalpha(body_mask)
    canvas = Image.alpha_composite(canvas, body)

    # inner light along the top of the body
    top_glow = Image.new("RGBA", (S, S), (255, 255, 255, 0))
    top_glow.putalpha(mul_masks(body_mask, vertical_ramp((S, S), 0.0, 0.0)))
    glow_band = vertical_ramp((S, S), 0.0, 0.0)
    ramp = np.zeros((S, S), np.float32)
    band = np.linspace(0.30, 0.0, int(S * 0.30))
    ramp[OFF:OFF + len(band), :] = band[:, None]
    top_glow.putalpha(mul_masks(body_mask, Image.fromarray((ramp * 255).astype(np.uint8), "L")))
    canvas = Image.alpha_composite(canvas, top_glow)

    # --- glass trackpad slab (frosted: blurred, brightened copy of what's behind)
    sw, sh = int(S * 0.50), int(S * 0.355)
    sx, sy = (S - sw) // 2, int(S * 0.43)
    slab_box = [sx, sy, sx + sw, sy + sh]
    slab_mask = rounded_mask((S, S), slab_box, int(S * 0.06))

    frosted = canvas.filter(ImageFilter.GaussianBlur(36))
    frosted = Image.blend(frosted, Image.new("RGBA", (S, S), (255, 255, 255, 255)), 0.22)
    frosted.putalpha(slab_mask)
    canvas = Image.alpha_composite(canvas, frosted)

    # slab drop shadow (below, soft)
    sshadow = Image.new("RGBA", (S, S), (20, 10, 70, 0))
    sshadow.putalpha(slab_mask.point(lambda v: int(v * 0.30)))
    sshadow = sshadow.transform(sshadow.size, Image.AFFINE, (1, 0, 0, 0, 1, -28)).filter(ImageFilter.GaussianBlur(34))
    # put shadow behind slab: composite shadow, then slab again
    under = Image.alpha_composite(canvas, sshadow)
    under.paste(canvas, (0, 0), slab_mask)
    canvas = under

    # slab rim: bright at the top, fading down
    rim = Image.new("RGBA", (S, S), (255, 255, 255, 0))
    rim.putalpha(mul_masks(ring(slab_mask, 5), vertical_ramp((S, S), 1.6, -0.2)))
    canvas = Image.alpha_composite(canvas, rim)
    rim2 = Image.new("RGBA", (S, S), (255, 255, 255, 0))
    rim2.putalpha(mul_masks(ring(slab_mask, 3), vertical_ramp((S, S), -0.6, 0.9)))
    canvas = Image.alpha_composite(canvas, rim2)

    # --- three fingers swiping down: glass dots with motion trails
    r = int(S * 0.048)
    cy = sy + int(sh * 0.62)
    xs = [S // 2 - int(S * 0.115), S // 2, S // 2 + int(S * 0.115)]
    ys = [cy + int(S * 0.012), cy - int(S * 0.012), cy + int(S * 0.012)]

    trails = Image.new("RGBA", (S, S), (255, 255, 255, 0))
    tmask = Image.new("L", (S, S), 0)
    td = ImageDraw.Draw(tmask)
    trail_len = int(S * 0.17)
    for x, y in zip(xs, ys):
        td.rounded_rectangle([x - int(r * 0.62), y - trail_len, x + int(r * 0.62), y], radius=int(r * 0.62), fill=255)
    ramp = np.zeros((S, S), np.float32)
    top, bottom = min(ys) - trail_len, max(ys)
    ramp[top:bottom, :] = np.linspace(0.0, 0.55, bottom - top)[:, None]
    trails.putalpha(mul_masks(tmask, Image.fromarray((ramp * 255).astype(np.uint8), "L")))
    canvas = Image.alpha_composite(canvas, trails.filter(ImageFilter.GaussianBlur(3)))

    for x, y in zip(xs, ys):
        box = [x - r, y - r, x + r, y + r]
        dmask = Image.new("L", (S, S), 0)
        ImageDraw.Draw(dmask).ellipse(box, fill=255)
        # shadow
        ds = Image.new("RGBA", (S, S), (30, 10, 90, 0))
        ds.putalpha(dmask.point(lambda v: int(v * 0.35)))
        ds = ds.transform(ds.size, Image.AFFINE, (1, 0, 0, 0, 1, -16)).filter(ImageFilter.GaussianBlur(18))
        canvas = Image.alpha_composite(canvas, ds)
        # glass body of the dot
        dot = gradient((S, S), [(0.0, "#FFFFFF"), (1.0, "#DCE6FF")], angle_xy=(0.0, 1.0))
        dot.putalpha(dmask.point(lambda v: int(v * 0.93)))
        canvas = Image.alpha_composite(canvas, dot)
        # small specular highlight
        hl = Image.new("RGBA", (S, S), (255, 255, 255, 0))
        hm = Image.new("L", (S, S), 0)
        ImageDraw.Draw(hm).ellipse([x - r * 0.55, y - r * 0.78, x + r * 0.15, y - r * 0.22], fill=200)
        hl.putalpha(hm.filter(ImageFilter.GaussianBlur(6)))
        canvas = Image.alpha_composite(canvas, hl)

    # --- body rim: specular edge, brightest at the top-left
    edge = Image.new("RGBA", (S, S), (255, 255, 255, 0))
    y, x = np.mgrid[0:S, 0:S].astype(np.float32)
    diag = np.clip(1.15 - (x + y) / (S * 1.1), 0.08, 1.0)
    edge_alpha = np.asarray(ring(body_mask, 4), np.float32) * diag
    edge.putalpha(Image.fromarray(edge_alpha.astype(np.uint8), "L"))
    canvas = Image.alpha_composite(canvas, edge)

    icon = canvas.resize((1024, 1024), Image.LANCZOS)
    icon.save(out / "AppIcon-1024.png")
    icon.save(out / "AppIcon.icns", sizes=[(16, 16), (32, 32), (64, 64), (128, 128),
                                          (256, 256), (512, 512), (1024, 1024)])
    print("wrote", out / "AppIcon.icns")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "Resources")
