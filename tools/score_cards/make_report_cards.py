# make_report_cards.py | v1.4.0
# v1.4.0: (Onur 2026-11-02) LSO box carries AIRBOSS's long grade: the grade word (lso_<code>.png, left) plus
#         grade.details on a 3 x 34 character grid (lx_<glyph>_<k>.png, k = row * LX_COLS + col, glyph names
#         in LX_GLYPHS); badges centred under the card: 15 half-pitch positions (badge_<ID>_<pos>.png,
#         n badges use pos 8-n, 10-n, ...). Flight_Report.lua >= v1.1.0 (LX_* / BADGE_POS checked).
# v1.3.1: Onur's metal bezel (src_art/report_frame_src.png, 2026-11-02) replaces the drawn bezel and rivets;
#         layout refitted inside it; carrier panel gets an explicit "LSO GRADE" row; NG shows "-- NO GRADE".
# v1.3.0: CRT pixel look of the Plane Captain cards (Onur 2026-11-02): metal bezel with rivets, black
#         panels with phosphor-green chamfered outlines, a grunge green band with black text, dot-matrix
#         large text / scanlined small text with glow. Font back to Share Tech Mono (monospace) everywhere.
#         The card ends at y CARD_B; the badges sit BELOW it on the transparent canvas (no badge strip).
#         Canvas, field slots and file names unchanged (Flight_Report.lua untouched); rows / labels moved.
# v1.2.0: card restyled to the badge art: black chamfered panels, green (55,245,40) / red (245,20,10), Oswald.
# v1.1.0: Onur's badge art (2026-11-02, square 1254 px): badges are square, 116 px on the card.
#         --import-badges DIR copies art named by the badge title ("Bankler 75.png", "Heavy at The Ramp.png", ...)
#         to src_art/badges/<ID>.png, downscaled to 400 px (repo size); unknown / missing names are listed.
# Report-card ("karne") layers for scripts/Flight_Report.lua v1.0.0 -> out/FlightReport/*.png
# (project doc claude/report-card-design-2026-11-02.md).
#
# Every layer is a full 1280x720 transparent canvas, so DCS overlays them exactly with one align/size.
#   frame.png                       card (bezel, panels, band, static labels)
#   grade_<SH|SAT|UNSAT>.png        overall grade word (top right)
#   stamp_<1|2|3>.png               ROE disposition stamp
#   lso_<code>.png                  LSO grade word: OK_U (_OK_) OK OKP ((OK)) NG (--) C WO B NONE DIV
#   carrier_na.png                  "NO CARRIER PASS"
#   <field>_<glyph>_<slot>.png      digits; glyph 0-9 | p (+) | m (-) | d (.); slot 0..N-1 left to right,
#                                   the value is right-aligned (Flight_Report.lua Field()); FIELDS below must
#                                   match CFG.FIELDS / GROUP_SLOTS there (checked by check_lua()).
#   lx_<glyph>_<k>.png              LSO long-grade characters, grid LX_ROWS x LX_COLS in the LSO box
#   badge_<ID>_<pos>.png            pos 0..14 (half-pitch), below the card, centred by Flight_Report.lua;
#                                   art from src_art/badges/<ID>.png, else a placeholder
# Dot-matrix / scanline grids are anchored to canvas pixels, so separate layers line up.
# Preview: out/preview/report_preview.png (+ report_preview_bg.png on a backdrop; not packed).
# Usage: python tools/score_cards/make_report_cards.py [--out DIR]   (Pillow, numpy; default DIR =
#        src/FlightReport, the template's copy; tools/sync_missions.py copies it into CAS (L))

import os
import re
import sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
FONTS = os.path.join(HERE, "fonts")
OUT = os.path.join(REPO, "src", "FlightReport")
PREV = os.path.join(HERE, "out", "preview")
BADGE_ART = os.path.join(HERE, "src_art", "badges")
LUA = os.path.join(REPO, "scripts", "Flight_Report.lua")

W, H = 1280, 720
CARD_B = 588                                          # v1.3.1 card bottom (bezel art); badges below
FRAME_ART = os.path.join(HERE, "src_art", "report_frame_src.png")
MONO = os.path.join(FONTS, "ShareTechMono-Regular.ttf")   # v1.3.0 the only font

# palette: badge green / red, Plane Captain card tones
C_LINE = (60, 250, 45)          # panel outlines, bright values
C_POS = (60, 250, 45)
C_LABEL = (38, 175, 30)         # dim labels
C_TEXT = (165, 255, 145)        # neutral values (total, LSO points, SAT, losses)
C_AMB = C_TEXT
C_NEG = (250, 35, 20)
C_GRID = (22, 85, 18)
C_BAND = (58, 200, 42)          # grunge band
C_INK = (4, 14, 4)              # black text on the band
BG_A = 246                      # panel opacity

GROUPS = ["Launch & departure", "Mission timing", "Aerial refuelling", "VUL / CAS procedure", "Targets",
          "Threat avoidance", "ROE / friendly fire", "Recovery", "Trap & deck", "Divert", "Mission events"]
ROW0, ROWH = 188, 33
G_E_RIGHT, G_P_RIGHT, G_H = 772, 856, 24

# field: (slots, right_x, top_y, height, colour, glyphs)
FIELDS = {
    "tot":    (5, 398, 186, 84, C_TEXT, "0123456789m"),
    "earn":   (4, 398, 312, 42, C_POS, "0123456789p"),
    "pen":    (4, 398, 394, 42, C_NEG, "0123456789m"),
    "loss":   (4, 398, 476, 42, C_AMB, "0123456789m"),
    "lsopts": (3, 1234, 342, 28, C_TEXT, "0123456789d"),
    "wire":   (1, 1234, 376, 28, C_TEXT, "1234"),
    "tgr":    (4, 1234, 410, 28, C_TEXT, "0123456789d"),
    "bk":     (2, 1056, 482, 34, C_TEXT, "0123456789"),
    "bkmax":  (2, 1128, 482, 34, C_LABEL, "0123456789"),
    "bkpct":  (3, 1206, 482, 34, C_AMB, "0123456789"),
}
for i in range(1, len(GROUPS) + 1):
    y = ROW0 + (i - 1) * ROWH
    FIELDS["g%de" % i] = (4, G_E_RIGHT, y, G_H, C_POS, "0123456789p")
    FIELDS["g%dp" % i] = (4, G_P_RIGHT, y, G_H, C_NEG, "0123456789m")
GROUP_SLOTS = 4

BADGES = [  # id, label, kind (A achievement / D demerit) - same ids as Flight_Report.lua BADGES
    ("BLUE_ON_BLUE", "BLUE ON\nBLUE", "D"), ("COWBOY", "COWBOY", "D"), ("SPEED_DEMON", "SPEED\nDEMON", "D"),
    ("OFF_CORRIDOR", "OFF\nCORRIDOR", "D"), ("HARD_DECK", "HARD\nDECK", "D"), ("BOLTER_CLUB", "BOLTER\nCLUB", "D"),
    ("HEAVY", "HEAVY", "D"), ("FUMES", "FUMES", "D"),
    ("BANKLER_75", "BANKLER\n75/75", "A"), ("BANKLER_70", "BANKLER\n70+", "A"), ("OK_PASS", "OK\nPASS", "A"),
    ("THREE_WIRE", "THREE\nWIRE", "A"), ("CLEAN_ROE", "CLEAN\nROE", "A"), ("SHACK", "SHACK", "A"),
    ("TIC_RESPONSE", "TIC\nRESPONSE", "A"), ("READBACK_ACE", "READBACK\nACE", "A"),
    ("DEFENSIVE_ACE", "DEFENSIVE\nACE", "A"), ("GHOST", "GHOST", "A"), ("FIRST_PLUG", "FIRST\nPLUG", "A"),
    ("ON_THE_PLAN", "ON THE\nPLAN", "A"), ("TIME_HACK", "TIME\nHACK", "A"),
    ("FUEL_DISCIPLINE", "FUEL\nDISCIPLINE", "A"), ("PARKING_PRO", "PARKING\nPRO", "A"),
]
BADGE_SLOTS, BADGE_W, BADGE_H = 8, 140, 120        # v1.3.0 row below the card, no strip; 8 badges at most
BADGE_POS = 2 * BADGE_SLOTS - 1                     # v1.4.0 half-pitch positions for centring
BADGE_GAP = 8
BADGE_X0 = (W - (BADGE_SLOTS * BADGE_W + (BADGE_SLOTS - 1) * BADGE_GAP)) // 2
BADGE_Y = CARD_B + (H - CARD_B - BADGE_H) // 2 + 2
ART_PX = 400   # v1.1.0 src_art/badges size

# v1.1.0: title-based file names (Onur's art folder) -> badge id; key = lower-case letters and digits only
ART_NAMES = {"bankler75": "BANKLER_75", "bankler7575": "BANKLER_75", "bankler70": "BANKLER_70",
             "okpass": "OK_PASS", "threewire": "THREE_WIRE", "cleanroe": "CLEAN_ROE", "shack": "SHACK",
             "ticresponse": "TIC_RESPONSE", "readbackace": "READBACK_ACE", "defensiveace": "DEFENSIVE_ACE",
             "ghost": "GHOST", "firstplug": "FIRST_PLUG", "ontheplan": "ON_THE_PLAN", "timehack": "TIME_HACK",
             "fueldiscipline": "FUEL_DISCIPLINE", "parkingpro": "PARKING_PRO", "blueonblue": "BLUE_ON_BLUE",
             "cowboy": "COWBOY", "speeddemon": "SPEED_DEMON", "offcorridor": "OFF_CORRIDOR",
             "belowtheharddeck": "HARD_DECK", "harddeck": "HARD_DECK", "bolterclub": "BOLTER_CLUB",
             "heavyattheramp": "HEAVY", "heavy": "HEAVY", "onfumes": "FUMES", "fumes": "FUMES"}


def import_badges(src_dir):
    os.makedirs(BADGE_ART, exist_ok=True)
    done, unknown = set(), []
    for f in sorted(os.listdir(src_dir)):
        if not f.lower().endswith(".png"):
            continue
        key = re.sub(r"[^a-z0-9]", "", os.path.splitext(f)[0].lower())
        bid = ART_NAMES.get(key)
        if not bid:
            unknown.append(f)
            continue
        im = Image.open(os.path.join(src_dir, f)).convert("RGBA")
        im.thumbnail((ART_PX, ART_PX), Image.LANCZOS)
        im.save(os.path.join(BADGE_ART, bid + ".png"), optimize=True)
        done.add(bid)
        print("badge art: %-28s -> %s.png" % (f, bid))
    missing = [b[0] for b in BADGES if b[0] not in done]
    print("imported %d, unknown file names %s, ids without art %s" % (len(done), unknown, missing))


# v1.4.0 LSO long grade (AIRBOSS grade.details, upper-cased by Flight_Report.lua)
LX_ROWS, LX_COLS, LX_SIZE, LX_LINE = 3, 34, 17, 20
LX_GLYPHS = dict([(c, c) for c in "ABCDEFGHIKLMNOPRSTUVWXY"] +
                 [("lp", "("), ("rp", ")"), ("us", "_"), ("sl", "/"), ("bs", "\\"), ("m", "-"), ("d", ".")])

LSO = {"OK_U": ("_OK_", C_POS), "OK": ("OK", C_POS), "OKP": ("(OK)", C_AMB), "NG": ("-- NO GRADE", C_AMB),
       "C": ("CUT", C_NEG), "WO": ("WAVE-OFF", C_NEG), "B": ("BOLTER", C_NEG), "NONE": ("NO LSO GRADE", C_LABEL),
       "DIV": ("DIVERT", C_AMB)}
GRADES = {"SH": ("SIERRA HOTEL", C_POS), "SAT": ("SAT", C_AMB), "UNSAT": ("UNSAT", C_NEG)}
STAMPS = {1: "LETTER OF\nINSTRUCTION", 2: "REPRIMAND\nFNAEB", 3: "COURT-MARTIAL\nREVIEW"}
GLYPH = {"p": "+", "m": "-", "d": "."}

_ROWS = np.arange(H)[:, None]
SCAN = np.where(_ROWS % 3 == 2, 0.62, 1.0).astype(np.float32)     # canvas-anchored scanlines


def font(size):
    return ImageFont.truetype(MONO, size)


def canvas():
    return Image.new("RGBA", (W, H), (0, 0, 0, 0))


def save(im, name):
    im.save(os.path.join(OUT, name), optimize=True)


def check_lua():
    src = open(LUA, encoding="utf-8").read()
    m = re.search(r"FIELDS\s*=\s*\{([^}]*)\}", src)
    lua = dict((k, int(v)) for k, v in re.findall(r"(\w+)\s*=\s*(\d+)", m.group(1)))
    gs = int(re.search(r"GROUP_SLOTS\s*=\s*(\d+)", src).group(1))
    ids = re.findall(r'\{\s*"([A-Z_0-9]+)",\s*"[^"]*",\s*"[AD]"\s*\}', src)
    bad = [k for k, v in lua.items() if k not in FIELDS or FIELDS[k][0] != v]
    if gs != GROUP_SLOTS:
        bad.append("GROUP_SLOTS")
    missing = sorted(set(ids) ^ set(b[0] for b in BADGES))
    for key, want in (("BADGE_SLOTS", BADGE_SLOTS), ("LX_ROWS", LX_ROWS), ("LX_COLS", LX_COLS)):   # v1.4.0
        m = re.search(key + r"\s*=\s*(\d+)", src)
        if not m or int(m.group(1)) != want:
            bad.append(key)
    m = re.search(r"LX_GLYPH\s*=\s*\{([^}]*)\}", src)
    lua_g = dict((v, k) for k, v in re.findall(r'\["(.{1,2})"\]\s*=\s*"(\w+)"', m.group(1))) if m else {}
    lua_g = {k: v.replace("\\\\", "\\") for k, v in lua_g.items()}
    if lua_g != LX_GLYPHS:
        bad.append("LX_GLYPH")
    if bad or missing:
        sys.exit("Flight_Report.lua and this script disagree: fields %s, badges %s" % (bad, missing))



# ---------------------------------------------------------------- CRT rendering
def mask():
    return Image.new("L", (W, H), 0)


def phosphor(m, rgb, pitch=0, glow=0.55):
    """L mask -> RGBA. pitch>0: dot matrix on a canvas-anchored grid (gap 1 px); 0: scanlined strokes."""
    a = np.asarray(m, np.float32) / 255.0
    if pitch:
        hp, wp = H // pitch * pitch, W // pitch * pitch
        cov = a[:hp, :wp].reshape(hp // pitch, pitch, wp // pitch, pitch).mean(axis=(1, 3))
        lvl = np.clip((cov - 0.10) / 0.22, 0, 1)
        dot = np.ones((pitch, pitch), np.float32)
        dot[-1, :] = 0.18
        dot[:, -1] = 0.18
        core = np.zeros((H, W), np.float32)
        core[:hp, :wp] = np.kron(lvl, dot)
    else:
        core = a * SCAN
    g = Image.fromarray((np.clip(core, 0, 1) * 255).astype(np.uint8))
    g = np.asarray(g.filter(ImageFilter.GaussianBlur(max(2, pitch * 1.4))), np.float32) / 255.0
    alpha = np.clip(core + g * glow, 0, 1)
    hi = np.clip(core - 0.6, 0, 1) * 0.5                          # hot centres go a little paler
    rgb = np.array(rgb, np.float32)
    col = rgb[None, None, :] + (255 - rgb)[None, None, :] * hi[:, :, None]
    out = np.dstack([col, alpha[:, :, None] * 255]).clip(0, 255).astype(np.uint8)
    return Image.fromarray(out, "RGBA")


def text_m(m, xy, text, size, anchor="la", spacing=4, stroke=0):
    d = ImageDraw.Draw(m)
    if "\n" in text:
        d.multiline_text(xy, text, font=font(size), fill=255, anchor=anchor, align="center", spacing=spacing,
                         stroke_width=stroke, stroke_fill=255)
    else:
        d.text(xy, text, font=font(size), fill=255, anchor=anchor, stroke_width=stroke, stroke_fill=255)


def put_text(im, xy, text, size, rgb, pitch=None, anchor="la"):
    """pitch None: dot matrix from 30 px up, scanlined strokes below."""
    if pitch is None:
        pitch = 4 if size >= 56 else (3 if size >= 30 else 0)
    m = mask()
    text_m(m, xy, text, size, anchor, stroke={0: 0, 3: 1}.get(pitch, 2))   # dot matrix needs weight
    im.alpha_composite(phosphor(m, rgb, pitch))


def chamfer_pts(box, c):
    x0, y0, x1, y1 = box
    return [(x0 + c, y0), (x1 - c, y0), (x1, y0 + c), (x1, y1 - c), (x1 - c, y1), (x0 + c, y1), (x0, y1 - c),
            (x0, y0 + c)]


def noise(seed, scale, shape=(H, W)):
    r = np.random.default_rng(seed)
    n = Image.fromarray((r.random((shape[0] // scale + 2, shape[1] // scale + 2)) * 255).astype(np.uint8))
    n = n.resize((shape[1] + 2 * scale, shape[0] + 2 * scale), Image.BICUBIC).crop(
        (scale, scale, scale + shape[1], scale + shape[0]))
    return np.asarray(n, np.float32) / 255.0


def grunge(seed):
    """0..1 blotchy texture: large blotches + fine grain + a few scratches."""
    t = 0.55 * noise(seed, 40) + 0.30 * noise(seed + 1, 9) + 0.15 * np.random.default_rng(seed + 2).random((H, W))
    m = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(m)
    r = np.random.default_rng(seed + 3)
    for _ in range(70):
        x, y = r.integers(0, W), r.integers(0, H)
        d.line((x, y, x + r.integers(-60, 60), y + r.integers(-12, 12)), fill=int(r.integers(60, 160)), width=1)
    return np.clip(t - np.asarray(m, np.float32) / 255.0 * 0.5, 0, 1)


def fill_poly(im, pts, rgb, alpha, tex=None, tex_amt=0.0):
    pm = Image.new("L", (W, H), 0)
    ImageDraw.Draw(pm).polygon(pts, fill=255)
    a = np.asarray(pm, np.float32) / 255.0
    rgb = np.array(rgb, np.float32)
    k = 1.0 if tex is None else (1.0 - tex_amt) + tex_amt * tex * 1.3
    col = rgb[None, None, :] * (k[:, :, None] if tex is not None else 1.0) * SCAN[:, :, None] ** 0.35
    col = np.broadcast_to(col, (H, W, 3))
    lay = np.dstack([col, (a * alpha)[:, :, None]]).clip(0, 255).astype(np.uint8)
    im.alpha_composite(Image.fromarray(lay, "RGBA"))


def outline(im, box, c, rgb, width=3):
    m = mask()
    ImageDraw.Draw(m).polygon(chamfer_pts(box, c), outline=255, width=width)
    im.alpha_composite(phosphor(m, rgb, 0, glow=0.7))


def rivet(im, cx, cy, r=7):
    d = ImageDraw.Draw(im)
    d.ellipse((cx - r - 2, cy - r - 2, cx + r + 2, cy + r + 2), fill=(8, 10, 8, 255))
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(70, 78, 70, 255))
    d.ellipse((cx - r + 2, cy - r + 2, cx + r - 3, cy + r - 3), fill=(105, 115, 105, 255))
    d.line((cx - r + 3, cy + r - 3, cx + r - 3, cy - r + 3), fill=(35, 40, 35, 255), width=2)


# ---------------------------------------------------------------- layers
HDR_L, HDR_R = (28, 28, 864, 102), (876, 28, 1252, 102)
BAND = (28, 112, 1252, 144)
P_L, P_M, P_R = (28, 154, 418, 562), (430, 154, 864, 562), (876, 154, 1252, 562)
LSO_BOX = (892, 216, 1236, 334)
LX_X0, LX_Y0 = 904, 284                               # v1.4.0 first character cell (left, baseline)


def bezel(im):
    """Onur's bezel art scaled onto the card; its transparent inside (flood fill from the centre) is panel ground."""
    art = Image.open(FRAME_ART).convert("RGBA")
    art = art.crop(art.getchannel("A").point(lambda v: 255 if v > 40 else 0).getbbox())
    art = art.resize((W, CARD_B), Image.LANCZOS)
    inside = art.getchannel("A").point(lambda v: 255 if v > 90 else 0)
    ImageDraw.floodfill(inside, (W // 2, CARD_B // 2), 128)
    a = (np.asarray(inside) == 128).astype(np.float32)
    a = np.asarray(Image.fromarray((a * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(5)), np.float32) / 255
    a = np.pad(a, ((0, H - CARD_B), (0, 0)))
    ground = np.dstack([np.broadcast_to(np.array((3, 9, 3), np.float32), (H, W, 3)), (a * BG_A)[:, :, None]])
    im.alpha_composite(Image.fromarray(ground.astype(np.uint8), "RGBA"))
    full = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    full.paste(art, (0, 0))
    im.alpha_composite(full)


def frame():
    im = canvas()
    # metal bezel
    bezel(im)                                                          # v1.3.1 Onur's art
    # panels
    for box in (HDR_L, HDR_R, P_L, P_M, P_R):
        fill_poly(im, chamfer_pts(box, 16), (2, 10, 2), 255, grunge(23), 0.35)
        outline(im, box, 16, C_LINE, 3)
    fill_poly(im, chamfer_pts(BAND, 6), C_BAND, 255, grunge(37), 0.55)
    # static text
    put_text(im, (46, 65), "FLIGHT REPORT", 60, C_POS, anchor="lm")
    ink = mask()
    text_m(ink, (48, 128), "HORNET 51 · CAS-1 · F/A-18C", 22, "lm")
    text_m(ink, (1234, 128), "SORTIE DEBRIEF", 22, "rm")
    a = np.asarray(ink, np.float32) / 255.0 * SCAN ** 0.5
    im.alpha_composite(Image.fromarray(np.dstack([np.full((H, W, 3), C_INK, np.float32),
                                                  (a * 255)[:, :, None]]).astype(np.uint8), "RGBA"))
    lab = 22
    put_text(im, (46, 164), "TOTAL", lab, C_LABEL)
    put_text(im, (46, 288), "EARNED", lab, C_LABEL)
    put_text(im, (46, 370), "PENALTIES", lab, C_LABEL)
    put_text(im, (46, 452), "MISSION LOSSES", lab, C_LABEL)
    put_text(im, (46, 520), "(not in the total)", 16, C_LABEL)
    put_text(im, (46, 540), "F10 > INFO > FLIGHT REPORT", 14, C_GRID)
    put_text(im, (446, 164), "GROUP", 18, C_LABEL)
    put_text(im, (G_E_RIGHT, 164), "EARNED", 18, C_LABEL, anchor="ra")
    put_text(im, (G_P_RIGHT, 164), "PEN.", 18, C_LABEL, anchor="ra")
    m = mask()
    d = ImageDraw.Draw(m)
    for i, g in enumerate(GROUPS):
        y = ROW0 + i * ROWH
        d.text((446, y + G_H // 2 + 1), g, font=font(19), fill=255, anchor="lm")
    im.alpha_composite(phosphor(m, C_TEXT, 0))
    m = mask()
    d = ImageDraw.Draw(m)
    for i in range(len(GROUPS)):
        y = ROW0 + i * ROWH + ROWH - 5
        for x in range(444, 856, 4):                                   # dotted rule
            d.point((x, y), fill=255)
    im.alpha_composite(phosphor(m, C_GRID, 0, glow=0.2))
    put_text(im, (894, 164), "CARRIER RECOVERY", 22, C_LABEL)
    put_text(im, (894, 196), "LSO GRADE", 18, C_LABEL)                 # v1.3.1
    m = mask()
    ImageDraw.Draw(m).polygon(chamfer_pts(LSO_BOX, 8), outline=255, width=2)
    im.alpha_composite(phosphor(m, C_GRID, 0, glow=0.3))
    for y, t in ((356, "PASS PTS"), (390, "WIRE"), (424, "GROOVE s")):
        put_text(im, (894, y), t, 20, C_LABEL, anchor="lm")
    put_text(im, (894, 458), "BANKLER (not in total)", 16, C_LABEL)
    put_text(im, (1062, 499), "/", 34, C_LABEL, anchor="lm")
    put_text(im, (1236, 499), "%", 30, C_AMB, pitch=0, anchor="rm")   # dot matrix mangles %
    save(im, "frame.png")
    return im


def word(name, text, col, box, size, left=False):
    im = canvas()
    x0, y0, x1, y1 = box
    while font(size).getlength(text) > x1 - x0 and size > 12:
        size -= 2
    if left:
        put_text(im, (x0, (y0 + y1) / 2), text, size, col, anchor="lm")
    else:
        put_text(im, ((x0 + x1) / 2, (y0 + y1) / 2), text, size, col, anchor="mm")
    save(im, name)
    return im


def stamp(n, text):
    im = canvas()
    box = (500, 36, 840, 94)
    fill_poly(im, chamfer_pts(box, 10), (24, 2, 0), 245)
    outline(im, box, 10, C_NEG, 4)
    m = mask()
    text_m(m, ((box[0] + box[2]) / 2, (box[1] + box[3]) / 2 + 1), text, 24, "mm", spacing=2)
    im.alpha_composite(phosphor(m, C_NEG, 0, glow=0.7))
    save(im, "stamp_%d.png" % n)
    return im


def glyphs():
    n = 0
    for fld, (slots, right, top, h, col, gl) in FIELDS.items():
        size = int(h * 1.36)                       # Share Tech Mono: digit height ~0.70 em
        f = font(size)
        cell = f.getlength("0")
        pitch = 4 if h >= 70 else (3 if h >= 32 else 0)
        for slot in range(slots):
            cx = right - (slots - slot - 0.5) * cell
            for g in gl:
                im = canvas()
                put_text(im, (cx, top + h), GLYPH.get(g, g), size, col, pitch, anchor="ms")
                save(im, "%s_%s_%d.png" % (fld, g, slot))
                n += 1
    return n


def lso_chars():
    """v1.4.0 one layer per (glyph, cell) of the long-grade grid."""
    cell = font(LX_SIZE).getlength("0")
    n = 0
    for k in range(LX_ROWS * LX_COLS):
        r, c = divmod(k, LX_COLS)
        x, y = LX_X0 + (c + 0.5) * cell, LX_Y0 + r * LX_LINE
        for g, ch in LX_GLYPHS.items():
            im = canvas()
            put_text(im, (x, y), ch, LX_SIZE, C_TEXT, 0, anchor="ms")
            save(im, "lx_%s_%d.png" % (g, k))
            n += 1
    return n


def lx_files(text):
    """Preview twin of Flight_Report.lua LxFiles(): word wrap on spaces, hard split of long tokens."""
    inv = {v: k for k, v in LX_GLYPHS.items()}
    rows, cur = [], ""
    for tok in text.upper().split():
        while len(tok) > LX_COLS:
            if cur:
                rows.append(cur); cur = ""
            rows.append(tok[:LX_COLS]); tok = tok[LX_COLS:]
        if not cur:
            cur = tok
        elif len(cur) + 1 + len(tok) <= LX_COLS:
            cur += " " + tok
        else:
            rows.append(cur); cur = tok
    if cur:
        rows.append(cur)
    out = []
    for r, line in enumerate(rows[:LX_ROWS]):
        for c, ch in enumerate(line):
            if ch in inv:
                out.append("lx_%s_%d.png" % (inv[ch], r * LX_COLS + c))
    return out


def badge_art(bid, label, kind):
    side = min(BADGE_W, BADGE_H) - 4
    p = os.path.join(BADGE_ART, bid + ".png")
    if os.path.isfile(p):
        a = Image.open(p).convert("RGBA")
        a.thumbnail((side, side), Image.LANCZOS)
        return a
    a = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    d = ImageDraw.Draw(a)
    col = C_POS if kind == "A" else C_NEG
    d.polygon(chamfer_pts((2, 2, side - 3, side - 3), 14), fill=(4, 10, 4, 240), outline=col, width=3)
    d.multiline_text((side / 2, side / 2), label, font=font(16), fill=col, anchor="mm", align="center")
    return a


def badges():
    n = 0
    for bid, label, kind in BADGES:
        art = badge_art(bid, label, kind)
        for slot in range(BADGE_POS):                                  # v1.4.0 half-pitch positions
            im = canvas()
            x = round(BADGE_X0 + slot * (BADGE_W + BADGE_GAP) / 2 + (BADGE_W - art.width) / 2)
            im.alpha_composite(art, (x, BADGE_Y + (BADGE_H - art.height) // 2))
            save(im, "badge_%s_%d.png" % (bid, slot))
            n += 1
    return n


def backdrop():
    """Preview only: a hazy sky-to-ground gradient standing in for the DCS view."""
    y = np.linspace(0, 1, H)[:, None, None]
    top, bot = np.array([92, 112, 132]), np.array([62, 58, 48])
    g = (top * (1 - y) + bot * y) * np.ones((1, W, 1))
    return Image.fromarray(np.dstack([g, np.full((H, W, 1), 255)]).astype(np.uint8), "RGBA")


def preview(base):
    im = base.copy()

    def lay(name):
        im.alpha_composite(Image.open(os.path.join(OUT, name)))

    def fld(f, s, slots=None):
        slots = slots or FIELDS[f][0]
        off = slots - len(s)
        for i, ch in enumerate(s):
            g = {"+": "p", "-": "m", ".": "d"}.get(ch, ch)
            lay("%s_%s_%d.png" % (f, g, off + i))
    lay("grade_SAT.png"); fld("tot", "41"); fld("earn", "+87"); fld("pen", "-46"); fld("loss", "0")
    vals = [("+10", "0"), ("+5", "-1"), ("+13", "-3"), ("0", "0"), ("+42", "0"), ("0", "0"), ("0", "-15"),
            ("+10", "-19"), ("+7", "-5"), ("0", "0"), ("0", "0")]
    for i, (e, p) in enumerate(vals, 1):
        fld("g%de" % i, e); fld("g%dp" % i, p)
    lay("lso_OK.png"); fld("lsopts", "4.0")
    for f in lx_files("(LUL)X (F)IM (LO)IC _LUL_AR (LLWD)IW (LIG)"):
        lay(f)
    fld("wire", "2"); fld("tgr", "20.9")
    fld("bk", "60"); fld("bkmax", "75"); fld("bkpct", "80")
    lay("stamp_1.png")
    shown = ["READBACK_ACE", "FIRST_PLUG", "PARKING_PRO", "HEAVY", "SPEED_DEMON"]
    for i, b in enumerate(shown):                                     # centred like Flight_Report.lua
        lay("badge_%s_%d.png" % (b, BADGE_SLOTS - len(shown) + 2 * i))
    os.makedirs(PREV, exist_ok=True)
    im.save(os.path.join(PREV, "report_preview.png"))
    bg = backdrop()
    bg.alpha_composite(im)
    bg.convert("RGB").save(os.path.join(PREV, "report_preview_bg.png"))


def main():
    global OUT
    if "--import-badges" in sys.argv:                       # v1.1.0
        import_badges(sys.argv[sys.argv.index("--import-badges") + 1])
    if "--out" in sys.argv:
        OUT = os.path.abspath(sys.argv[sys.argv.index("--out") + 1])
    check_lua()
    os.makedirs(OUT, exist_ok=True)
    for f in os.listdir(OUT):
        if f.endswith(".png"):
            os.remove(os.path.join(OUT, f))
    base = frame()
    for k, (t, c) in GRADES.items():
        word("grade_%s.png" % k, t, c, (HDR_R[0] + 16, HDR_R[1], HDR_R[2] - 16, HDR_R[3]), 60)
    for k, (t, c) in LSO.items():
        word("lso_%s.png" % k, t, c, (LSO_BOX[0] + 12, LSO_BOX[1] + 4, LSO_BOX[2] - 12, LSO_BOX[1] + 48), 44, left=True)
    word("carrier_na.png", "NO CARRIER PASS", C_LABEL, (LSO_BOX[0] + 8, LSO_BOX[1], LSO_BOX[2] - 8, LSO_BOX[3]), 28)
    for n, t in STAMPS.items():
        stamp(n, t)
    ng = glyphs()
    nl = lso_chars()
    nb = badges()
    preview(base)
    files = os.listdir(OUT)
    size = sum(os.path.getsize(os.path.join(OUT, f)) for f in files)
    print("%d files (%d digit, %d LSO character, %d badge layers), %.1f MB -> %s"
          % (len(files), ng, nl, nb, size / 1e6, OUT))


if __name__ == "__main__":
    main()
