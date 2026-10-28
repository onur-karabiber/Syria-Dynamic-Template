# make_pc_cards.py | v1.2.0
# v1.2.0: --suffix S (e.g. _CRT_borderless): reads <id><S>_corrected.png if present, else
#         <id><S>.png (Onur's CRT cards 2026-10-28, C8 has a _corrected copy).
# Plane captain step cards for PlaneCaptain_Carrier (via Score_Display, CAS (L) only).
#
#   python tools/score_cards/make_pc_cards.py "<Saved Games>/DCS/Missions/The Routine Things (With RAT)/Pics"
#
# Reads <src>/<STEP>.png for every id in IDS (missing ids are reported and skipped:
# that step stays text-only), puts each on one common transparent canvas (largest
# source size), anchored ANCHOR, scales the canvas to WIDTH px, quantises to 256
# colours (saved back as RGBA) and writes out/PlaneCaptain/<STEP>.png, plus
# blank.png (2x2 transparent, used with clearView=true to remove the last card).
# Source art stays in Onur's Pics folder (not committed).
# v1.1.0: S_END / C_END added; stale cards in out/PlaneCaptain (ids no longer in the
#         source folder) are removed, so the output always matches the source set.
#
# Same canvas for every card -> identical align/size arguments put every card at
# the same screen spot. Change ANCHOR together with Score_Display CFG.PC (h/v).

import os
import sys
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out", "PlaneCaptain")

IDS = ["S00", "S0P", "S2", "S2W", "S3", "S3W", "S4", "S_END",
       "C1", "C2", "C3", "C4", "C5", "C6", "C7", "C8", "C9", "C10", "C11", "C12", "C13", "C14", "C_END"]
WIDTH = 1000
SUFFIX = ""                          # v1.2.0: set by --suffix
ANCHOR = ("left", "top")             # v1.0.1: matches Score_Display CFG.PC h = 0, v = 0


def main(src):
    found = {}
    for i in IDS:
        p = os.path.join(src, i + SUFFIX + "_corrected.png")
        if not os.path.isfile(p):
            p = os.path.join(src, i + SUFFIX + ".png")
        if os.path.isfile(p):
            found[i] = Image.open(p).convert("RGBA")
        else:
            print("missing (text only):", i)
    if not found:
        sys.exit("no cards in " + src)
    cw = max(im.width for im in found.values())
    ch = max(im.height for im in found.values())
    s = WIDTH / cw
    W, H = WIDTH, round(ch * s)
    os.makedirs(OUT, exist_ok=True)
    for f in os.listdir(OUT):
        if f.endswith(".png") and f != "blank.png" and f[:-4] not in found:
            os.remove(os.path.join(OUT, f))
            print("removed stale:", f)
    total = 0
    for i, im in found.items():
        canvas = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
        x = 0 if ANCHOR[0] == "left" else (cw - im.width if ANCHOR[0] == "right" else (cw - im.width) // 2)
        y = ch - im.height if ANCHOR[1] == "bottom" else (0 if ANCHOR[1] == "top" else (ch - im.height) // 2)
        canvas.paste(im, (x, y))
        out = canvas.resize((W, H), Image.LANCZOS)
        out = out.quantize(256, method=Image.Quantize.FASTOCTREE,
                           dither=Image.Dither.FLOYDSTEINBERG).convert("RGBA")
        fn = os.path.join(OUT, i + ".png")
        out.save(fn, optimize=True)
        total += os.path.getsize(fn)
    Image.new("RGBA", (2, 2), (0, 0, 0, 0)).save(os.path.join(OUT, "blank.png"))
    print("cards %d, canvas %dx%d (src %dx%d), %d bytes -> %s" % (len(found), W, H, cw, ch, total, OUT))


if __name__ == "__main__":
    a = sys.argv[1:]
    if "--suffix" in a:
        k = a.index("--suffix")
        SUFFIX = a[k + 1]
        del a[k:k + 2]
    if len(a) != 1:
        sys.exit("usage: make_pc_cards.py <cards folder> [--suffix _CRT_borderless]")
    main(a[0])
