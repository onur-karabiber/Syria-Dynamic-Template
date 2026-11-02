# make_report_cards.py | v1.1.0
# v1.1.0: Onur's badge art (2026-11-02, square 1254 px): badges are square, 116 px on the card (strip y 594..714).
#         --import-badges DIR copies art named by the badge title ("Bankler 75.png", "Heavy at The Ramp.png", ...)
#         to src_art/badges/<ID>.png, downscaled to 400 px (repo size); unknown / missing names are listed.
# Report-card ("karne") layers for scripts/Flight_Report.lua v1.0.0 -> out/FlightReport/*.png
# (project doc claude/report-card-design-2026-11-02.md). Placeholder art: Onur replaces it later.
#
# Every layer is a full 1280x720 transparent canvas, so DCS overlays them exactly with one align/size.
#   frame.png                       panel, static labels (groups, column heads, carrier rows)
#   grade_<SH|SAT|UNSAT>.png        overall grade word (top right)
#   stamp_<1|2|3>.png               ROE disposition stamp
#   lso_<code>.png                  LSO grade word: OK_U (_OK_) OK OKP ((OK)) NG (--) C WO B NONE DIV
#   carrier_na.png                  "NO CARRIER PASS"
#   <field>_<glyph>_<slot>.png      digits; glyph 0-9 | p (+) | m (-) | d (.); slot 0..N-1 left to right,
#                                   the value is right-aligned (Flight_Report.lua Field()); FIELDS below must
#                                   match CFG.FIELDS / GROUP_SLOTS there (checked by check_lua()).
#   badge_<ID>_<slot>.png           slot 0..7; art from src_art/badges/<ID>.png when present, else a placeholder
# Preview: out/preview/report_preview.png (not packed).
# Usage: python tools/score_cards/make_report_cards.py [--out DIR]   (Pillow; default DIR = src/FlightReport,
#        the template's copy; tools/sync_missions.py copies it into CAS (L))

import os
import re
import sys
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
FONTS = os.path.join(HERE, "fonts")
OUT = os.path.join(REPO, "src", "FlightReport")
PREV = os.path.join(HERE, "out", "preview")
BADGE_ART = os.path.join(HERE, "src_art", "badges")
LUA = os.path.join(REPO, "scripts", "Flight_Report.lua")

W, H = 1280, 720
MONO = os.path.join(FONTS, "ShareTechMono-Regular.ttf")
HEAD = os.path.join(FONTS, "BlackOpsOne-Regular.ttf")
STEN = os.path.join(FONTS, "StardosStencil-Bold.ttf")

C_BG = (10, 18, 28, 236)
C_LINE = (70, 110, 140, 255)
C_LABEL = (150, 185, 205, 255)
C_TEXT = (230, 238, 242, 255)
C_POS = (95, 255, 140, 255)
C_NEG = (255, 90, 74, 255)
C_AMB = (255, 196, 70, 255)

GROUPS = ["Launch & departure", "Mission timing", "Aerial refuelling", "VUL / CAS procedure", "Targets",
          "Threat avoidance", "ROE / friendly fire", "Recovery", "Trap & deck", "Divert", "Mission events"]
ROW0, ROWH = 168, 38
G_E_RIGHT, G_P_RIGHT, G_H = 772, 860, 26

# field: (slots, right_x, top_y, height, colour, glyphs)
FIELDS = {
    "tot":    (5, 400, 150, 86, C_TEXT, "0123456789m"),
    "earn":   (4, 400, 300, 44, C_POS, "0123456789p"),
    "pen":    (4, 400, 392, 44, C_NEG, "0123456789m"),
    "loss":   (4, 400, 484, 44, C_AMB, "0123456789m"),
    "lsopts": (3, 1232, 262, 30, C_TEXT, "0123456789d"),
    "wire":   (1, 1232, 302, 30, C_TEXT, "1234"),
    "tgr":    (4, 1232, 342, 30, C_TEXT, "0123456789d"),
    "bk":     (2, 1060, 420, 34, C_TEXT, "0123456789"),
    "bkmax":  (2, 1128, 420, 34, C_LABEL, "0123456789"),
    "bkpct":  (3, 1206, 420, 34, C_AMB, "0123456789"),
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
BADGE_SLOTS, BADGE_Y, BADGE_W, BADGE_H, BADGE_X0 = 8, 594, 140, 120, 48   # v1.1.0 square art, 116 px
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

LSO = {"OK_U": ("_OK_", C_POS), "OK": ("OK", C_POS), "OKP": ("(OK)", C_AMB), "NG": ("--", C_AMB),
       "C": ("CUT", C_NEG), "WO": ("WAVE-OFF", C_NEG), "B": ("BOLTER", C_NEG), "NONE": ("NOT GRADED", C_LABEL),
       "DIV": ("DIVERT", C_AMB)}
GRADES = {"SH": ("SIERRA HOTEL", C_POS), "SAT": ("SAT", C_AMB), "UNSAT": ("UNSAT", C_NEG)}
STAMPS = {1: "LETTER OF\nINSTRUCTION", 2: "REPRIMAND\nFNAEB", 3: "COURT-MARTIAL\nREVIEW"}
GLYPH = {"p": "+", "m": "-", "d": "."}


def font(path, size):
    return ImageFont.truetype(path, size)


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
    if bad or missing:
        sys.exit("Flight_Report.lua and this script disagree: fields %s, badges %s" % (bad, missing))


def frame():
    im = canvas()
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((4, 4, W - 5, H - 5), 22, fill=C_BG, outline=C_LINE, width=3)
    d.text((40, 26), "FLIGHT REPORT", font=font(HEAD, 44), fill=C_TEXT)
    d.text((44, 82), "HORNET 51  ·  CAS-1  ·  F/A-18C", font=font(MONO, 22), fill=C_LABEL)
    d.line((30, 128, W - 30, 128), fill=C_LINE, width=2)
    lab = font(MONO, 22)
    d.text((44, 138), "TOTAL", font=lab, fill=C_LABEL)
    d.text((44, 276), "EARNED", font=lab, fill=C_LABEL)
    d.text((44, 368), "PENALTIES", font=lab, fill=C_LABEL)
    d.text((44, 460), "MISSION LOSSES", font=lab, fill=C_LABEL)
    d.text((44, 532), "(not in the total)", font=font(MONO, 16), fill=C_LABEL)
    d.line((430, 140, 430, 580), fill=C_LINE, width=1)
    d.line((880, 140, 880, 580), fill=C_LINE, width=1)
    d.text((446, 138), "GROUP", font=font(MONO, 18), fill=C_LABEL)
    d.text((710, 138), "EARNED", font=font(MONO, 18), fill=C_LABEL)
    d.text((806, 138), "PEN.", font=font(MONO, 18), fill=C_LABEL)
    gf = font(MONO, 20)
    for i, g in enumerate(GROUPS):
        y = ROW0 + i * ROWH
        d.text((446, y + 2), g, font=gf, fill=C_TEXT)
        d.line((444, y + ROWH - 6, 866, y + ROWH - 6), fill=(40, 60, 80, 255), width=1)
    d.text((896, 138), "CARRIER", font=font(MONO, 22), fill=C_LABEL)
    for y, t in ((266, "PASS PTS"), (306, "WIRE"), (346, "GROOVE s")):
        d.text((896, y), t, font=gf, fill=C_LABEL)
    d.text((896, 392), "BANKLER (not in the total)", font=font(MONO, 16), fill=C_LABEL)
    d.text((1068, 418), "/", font=font(MONO, 34), fill=C_LABEL)
    d.text((1210, 418), "%", font=font(MONO, 34), fill=C_AMB)
    d.line((30, 588, W - 30, 588), fill=C_LINE, width=2)
    d.text((44, 556), "F10 > INFO > FLIGHT REPORT: score detail", font=font(MONO, 14), fill=C_LABEL)
    save(im, "frame.png")
    return im


def word(name, text, col, box, size, fnt=HEAD):
    im = canvas()
    d = ImageDraw.Draw(im)
    f = font(fnt, size)
    x0, y0, x1, y1 = box
    while True:
        bb = d.textbbox((0, 0), text, font=f)
        if bb[2] - bb[0] <= x1 - x0 or size <= 12:
            break
        size -= 2
        f = font(fnt, size)
    tw, th = bb[2] - bb[0], bb[3] - bb[1]
    d.text((x0 + (x1 - x0 - tw) / 2 - bb[0], y0 + (y1 - y0 - th) / 2 - bb[1]), text, font=f, fill=col)
    save(im, name)
    return im


def stamp(n, text):
    sw, sh = 330, 104
    s = Image.new("RGBA", (sw, sh), (0, 0, 0, 0))
    d = ImageDraw.Draw(s)
    col = (225, 40, 40, 235)
    d.rounded_rectangle((4, 4, sw - 5, sh - 5), 10, outline=col, width=5)
    f = font(STEN, 30)
    bb = d.multiline_textbbox((0, 0), text, font=f, align="center", spacing=2)
    d.multiline_text(((sw - (bb[2] - bb[0])) / 2 - bb[0], (sh - (bb[3] - bb[1])) / 2 - bb[1]), text, font=f,
                     fill=col, align="center", spacing=2)
    s = s.rotate(6, expand=True, resample=Image.BICUBIC)
    im = canvas()
    im.alpha_composite(s, (655 - s.width // 2, 66 - s.height // 2))   # header, between title and grade
    save(im, "stamp_%d.png" % n)
    return im


def glyphs():
    n = 0
    for fld, (slots, right, top, h, col, gl) in FIELDS.items():
        f = font(MONO, int(h * 1.18))
        cell = int(h * 0.62)
        for slot in range(slots):
            cx = right - (slots - slot - 0.5) * cell
            for g in gl:
                im = canvas()
                d = ImageDraw.Draw(im)
                ch = GLYPH.get(g, g)
                bb = d.textbbox((0, 0), ch, font=f)
                d.text((cx - (bb[2] - bb[0]) / 2 - bb[0], top + h - bb[3]), ch, font=f, fill=col)
                save(im, "%s_%s_%d.png" % (fld, g, slot))
                n += 1
    return n


def badge_art(bid, label, kind):
    p = os.path.join(BADGE_ART, bid + ".png")
    if os.path.isfile(p):
        a = Image.open(p).convert("RGBA")
        side = min(BADGE_W - 8, BADGE_H - 4)   # v1.1.0 square art
        a.thumbnail((side, side), Image.LANCZOS)
        return a
    a = Image.new("RGBA", (BADGE_W - 8, BADGE_H - 4), (0, 0, 0, 0))
    d = ImageDraw.Draw(a)
    col = C_POS if kind == "A" else C_NEG
    fill = (20, 60, 35, 235) if kind == "A" else (70, 20, 20, 235)
    d.rounded_rectangle((2, 2, a.width - 3, a.height - 3), 16, fill=fill, outline=col, width=3)
    f = font(MONO, 18)
    bb = d.multiline_textbbox((0, 0), label, font=f, align="center")
    d.multiline_text(((a.width - (bb[2] - bb[0])) / 2 - bb[0], (a.height - (bb[3] - bb[1])) / 2 - bb[1]), label,
                     font=f, fill=C_TEXT, align="center")
    return a


def badges():
    n = 0
    for bid, label, kind in BADGES:
        art = badge_art(bid, label, kind)
        for slot in range(BADGE_SLOTS):
            im = canvas()
            x = BADGE_X0 + slot * (BADGE_W + 8) + (BADGE_W - art.width) // 2
            im.alpha_composite(art, (x, BADGE_Y + (BADGE_H - art.height) // 2))
            save(im, "badge_%s_%d.png" % (bid, slot))
            n += 1
    return n


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
    lay("lso_NG.png"); fld("lsopts", "2.0"); fld("wire", "2"); fld("tgr", "20.9")
    fld("bk", "60"); fld("bkmax", "75"); fld("bkpct", "80")
    lay("stamp_1.png")
    for name in ("badge_READBACK_ACE_0.png", "badge_FIRST_PLUG_1.png", "badge_PARKING_PRO_2.png",
                 "badge_HEAVY_5.png", "badge_SPEED_DEMON_6.png", "badge_COWBOY_7.png"):
        lay(name)
    os.makedirs(PREV, exist_ok=True)
    im.save(os.path.join(PREV, "report_preview.png"))


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
        word("grade_%s.png" % k, t, c, (900, 22, 1250, 118), 64)
    for k, (t, c) in LSO.items():
        word("lso_%s.png" % k, t, c, (896, 172, 1250, 246), 54)
    word("carrier_na.png", "NO CARRIER PASS", C_LABEL, (896, 172, 1250, 246), 34, MONO)
    for n, t in STAMPS.items():
        stamp(n, t)
    ng = glyphs()
    nb = badges()
    preview(base)
    files = os.listdir(OUT)
    size = sum(os.path.getsize(os.path.join(OUT, f)) for f in files)
    print("%d files (%d digit layers, %d badge layers), %.1f MB -> %s" % (len(files), ng, nb, size / 1e6, OUT))


if __name__ == "__main__":
    main()
