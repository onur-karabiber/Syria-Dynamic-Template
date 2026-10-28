# make_cards.py | v0.2.0
# v0.2.0: Onur's "CRT borderless" art (green phosphor, 2026-10-28): CRT 1254x1254,
#         medal 1333x1180; boxes re-measured; digits green (total), bright green (+),
#         red (-); medal digits phosphor green.
# Score card asset generator for Score_Display (CAS (L) only).
#
# Output (out/ScoreCards/):
#   crt_frame.png               CRT card frame (shown on every score change)
#   med_frame.png               medal card frame (shown at mission end)
#   <set>_<glyph>_<slot>.png    full-canvas transparent digit layers
#       set   : crt_t (CRT total, orange) | crt_dp (CRT delta +, green)
#               crt_dn (CRT delta -, red) | med_t (medal total, cream)
#       glyph : 0..9 | p (+) | m (-)
#       slot  : 0..6 -> horizontal offset (slot-3) * cell/2 from the set's
#               centre. A string of length L uses slots 2*(i-1)-(L-1)+3,
#               so 1..4 characters stay centred with only 7 positions.
#   Every layer of a card has the frame's exact pixel size, so DCS draws
#   them on top of each other with identical align/size arguments.
# Preview composites go to out/preview/ (not packed into the .miz).
#
# Usage:  python make_cards.py        (needs Pillow + numpy)

import os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "src_art")
FONTS = os.path.join(HERE, "fonts")
OUT = os.path.join(HERE, "out", "ScoreCards")
PREV = os.path.join(HERE, "out", "preview")

GLYPHS = {"0": "0", "1": "1", "2": "2", "3": "3", "4": "4", "5": "5",
          "6": "6", "7": "7", "8": "8", "9": "9", "p": "+", "m": "−"}

# ------------------------------------------------------------------
# Card geometry. Box coordinates are measured on the source art
# (src_art/*.png) and scaled to the output canvas width.
# ------------------------------------------------------------------
CARDS = {
    "crt": {
        "src": "crt_frame_src.png",
        "width": 512,
        "box": (205, 576, 1060, 940),         # dashed box (src px, v0.2.0)
    },
    "med": {
        "src": "medal_frame_src.png",
        "width": 768,
        "box": (100, 760, 1235, 1095),        # inner dark panel (src px, v0.2.0)
    },
}

# Digit sets: which card, glyphs, centre/height as fractions of the box.
SETS = {
    "crt_t": dict(card="crt", glyphs="0123456789m", font="BlackOpsOne-Regular.ttf",
                  cx=0.50, base=0.64, h=0.44, style="crt", rgb=(140, 255, 120)),
    "crt_dp": dict(card="crt", glyphs="0123456789p", font="BlackOpsOne-Regular.ttf",
                   cx=0.50, base=0.91, h=0.17, style="crt", rgb=(215, 255, 205)),
    "crt_dn": dict(card="crt", glyphs="0123456789m", font="BlackOpsOne-Regular.ttf",
                   cx=0.50, base=0.91, h=0.17, style="crt", rgb=(255, 70, 50)),
    "med_t": dict(card="med", glyphs="0123456789m", font="BlackOpsOne-Regular.ttf",
                  cx=0.50, base=0.78, h=0.58, style="medal", rgb=(140, 250, 125)),
}


def load_frame(card):
    c = CARDS[card]
    im = Image.open(os.path.join(SRC, c["src"])).convert("RGBA")
    s = c["width"] / im.width
    im = im.resize((c["width"], round(im.height * s)), Image.LANCZOS)
    x0, y0, x1, y1 = [v * s for v in c["box"]]
    return im, (x0, y0, x1, y1)


def font_for(spec, box):
    """Font size so that a digit's ink height = spec.h * box height."""
    target = spec["h"] * (box[3] - box[1])
    path = os.path.join(FONTS, spec["font"])
    size = int(target)
    for _ in range(6):
        f = ImageFont.truetype(path, size)
        bb = f.getbbox("8", anchor="ls")
        ink = bb[3] - bb[1]
        size = max(8, int(round(size * target / ink)))
    return ImageFont.truetype(path, size)


def cell_width(font):
    return max(font.getlength(GLYPHS[g]) for g in GLYPHS) * 0.92


def glyph_mask(size, font, ch, x, y):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).text((x, y), ch, font=font, fill=255, anchor="ms")
    return m


def style_crt(mask, rgb):
    """Phosphor look: scanlines in the glyph, soft glow around it."""
    w, h = mask.size
    a = np.asarray(mask, dtype=np.float32) / 255.0
    scan = np.ones((h, 1), np.float32)
    scan[::3] = 0.72                                   # every 3rd row darker
    core = a * scan
    glow = np.asarray(mask.filter(ImageFilter.GaussianBlur(w * 0.012)), np.float32) / 255.0
    halo = np.asarray(mask.filter(ImageFilter.GaussianBlur(w * 0.035)), np.float32) / 255.0
    alpha = np.clip(core + 0.55 * glow + 0.35 * halo, 0, 1)
    r, g, b = rgb
    hot = np.clip(core * 0.35, 0, 1)                   # whiter centre of the stroke
    rgbA = np.zeros((h, w, 4), np.float32)
    rgbA[..., 0] = r + (255 - r) * hot
    rgbA[..., 1] = g + (255 - g) * hot
    rgbA[..., 2] = b + (255 - b) * hot
    rgbA[..., 3] = alpha * 255
    return Image.fromarray(np.clip(rgbA, 0, 255).astype(np.uint8), "RGBA")


def style_medal(mask, rgb, seed):
    """Painted stencil look: worn edges, chipped paint, hard drop shadow."""
    w, h = mask.size
    rng = np.random.default_rng(seed)
    a = np.asarray(mask, dtype=np.float32) / 255.0
    # chipped paint: blurred noise thresholded into small holes
    n = Image.fromarray((rng.random((h, w)) * 255).astype(np.uint8), "L")
    n = np.asarray(n.filter(ImageFilter.GaussianBlur(1.6)), np.float32) / 255.0
    chips = (n < 0.40).astype(np.float32) * 0.85
    paint = a * (1.0 - chips)
    shade = 0.88 + 0.12 * (n - 0.5) * 2                # slight tonal grain
    # shadow: offset + blur of the clean mask
    off = int(max(2, w * 0.006))
    sh = Image.new("L", mask.size, 0)
    sh.paste(mask, (off, off))
    sh = np.asarray(sh.filter(ImageFilter.GaussianBlur(w * 0.004)), np.float32) / 255.0
    r, g, b = rgb
    out = np.zeros((h, w, 4), np.float32)
    sa = sh * 0.75 * (1 - paint)
    alpha = paint + sa
    safe = np.where(alpha > 0, alpha, 1)
    for i, c in enumerate((r, g, b)):
        out[..., i] = (paint * c * shade + sa * 8) / safe
    out[..., 3] = alpha * 255
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGBA")


def main():
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(PREV, exist_ok=True)
    frames = {}
    for card in CARDS:
        im, box = load_frame(card)
        frames[card] = (im, box)
        # 256-colour quantise (visually identical on this art), saved back
        # as plain RGBA: paletted PNG support in DCS is untested.
        q = im.quantize(256, method=Image.Quantize.FASTOCTREE,
                        dither=Image.Dither.FLOYDSTEINBERG).convert("RGBA")
        q.save(os.path.join(OUT, "%s_frame.png" % card), optimize=True)
        print("frame", card, im.size)

    layers = {}
    for name, spec in SETS.items():
        frame, box = frames[spec["card"]]
        font = font_for(spec, box)
        cw = cell_width(font)
        bw, bh = box[2] - box[0], box[3] - box[1]
        cx = box[0] + spec["cx"] * bw
        by = box[1] + spec["base"] * bh
        for gi, g in enumerate(spec["glyphs"]):
            for slot in range(7):
                x = cx + (slot - 3) * cw / 2
                m = glyph_mask(frame.size, font, GLYPHS[g], x, by)
                if spec["style"] == "crt":
                    lay = style_crt(m, spec["rgb"])
                else:
                    lay = style_medal(m, spec["rgb"], seed=gi * 7 + slot)
                fn = "%s_%s_%d.png" % (name, g, slot)
                lay.save(os.path.join(OUT, fn), optimize=True)
                layers[fn] = lay
        print("set", name, "font px", font.size, "cell", round(cw, 1))

    # previews: same composition rule the Lua uses
    def compose(card, parts):
        im = frames[card][0].copy()
        for set_name, text in parts:
            L = len(text)
            for i, ch in enumerate(text):
                g = {"+": "p", "-": "m"}.get(ch, ch)
                slot = 2 * i - (L - 1) + 3
                im.alpha_composite(layers["%s_%s_%d.png" % (set_name, g, slot)])
        return im

    compose("crt", [("crt_t", "42"), ("crt_dp", "+5")]).save(os.path.join(PREV, "crt_42_plus5.png"))
    compose("crt", [("crt_t", "-123"), ("crt_dn", "-15")]).save(os.path.join(PREV, "crt_m123_minus15.png"))
    compose("crt", [("crt_t", "7"), ("crt_dp", "+120")]).save(os.path.join(PREV, "crt_7_plus120.png"))
    compose("med", [("med_t", "87")]).save(os.path.join(PREV, "med_87.png"))
    compose("med", [("med_t", "-123")]).save(os.path.join(PREV, "med_m123.png"))

    # path-probe images for Score_Display_Test (stamped so the pilot can
    # tell which file-name form DCS resolved). Packed only into the test .miz.
    test_dir = os.path.join(HERE, "out", "test")
    os.makedirs(test_dir, exist_ok=True)
    frame, box = frames["crt"]
    f = ImageFont.truetype(os.path.join(FONTS, "BlackOpsOne-Regular.ttf"), 34)
    for fn, label in (("sc_test_root.png", "P1  ROOT PATH"),
                      ("sc_test_l10n.png", "P2-P4  L10N")):
        im = frame.copy()
        d = ImageDraw.Draw(im)
        d.text(((box[0] + box[2]) / 2, (box[1] + box[3]) / 2), label, font=f,
               fill=(255, 150, 30, 255), anchor="mm")
        im.save(os.path.join(test_dir, fn), optimize=True)

    total = sum(os.path.getsize(os.path.join(OUT, f)) for f in os.listdir(OUT))
    print("files", len(os.listdir(OUT)), "bytes", total)


if __name__ == "__main__":
    main()
