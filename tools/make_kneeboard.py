# make_kneeboard.py | v3.0.0
# Generates src/KNEEBOARD/images/01..05 *.png (CAS-1 kneeboard, 512x768).
# v3.0.0: all five cards generated from data below (01/03/04/05 were hand-made
#         PNGs). Content sits inside a margin (MX/MY) because the F/A-18C
#         kneeboard clip covers the card edges in flight. 03: Marshal = COMM1-16
#         261.00 AM. Replaces make_kneeboard_comm.py.
# Usage: python tools/make_kneeboard.py [out_dir]   (default src/KNEEBOARD/images)
# Needs Pillow and DejaVu Sans Mono (Windows: put DejaVuSansMono*.ttf next to this
# file or set KB_FONT_DIR).
import os, sys
from PIL import Image, ImageDraw, ImageFont

W, H   = 512, 768
MX, MY = 26, 18                     # margin (clip-free area)
IW, IH = W - 2 * MX, H - 2 * MY

BG=(248,244,234); BAND=(230,225,212); NAVY=(15,22,40); ORG=(232,150,20)
TXT=(30,30,30); GRN=(28,100,40); TAG=(182,118,0); GRY=(150,145,135); RULE=(210,206,196)
RED=(170,30,30); OCH=(190,95,20); YEL=(185,135,20)
COL = {"t": TXT, "g": GRN, "o": OCH, "r": RED, "y": YEL, "m": GRY, "a": TAG}

def font(bold, size):
    names = ["DejaVuSansMono-Bold.ttf" if bold else "DejaVuSansMono.ttf"]
    dirs = [os.environ.get("KB_FONT_DIR", ""), os.path.dirname(os.path.abspath(__file__)),
            "/usr/share/fonts/truetype/dejavu", "C:/Windows/Fonts"]
    for d in dirs:
        for n in names:
            p = os.path.join(d, n)
            if d and os.path.isfile(p): return ImageFont.truetype(p, size)
    raise SystemExit("DejaVu Sans Mono not found (set KB_FONT_DIR)")

F13, F11, F10 = font(False, 13), font(False, 11), font(False, 10)
B11, B10, BT = font(True, 11), font(True, 10), font(True, 20)
VX = 160   # value column (inner coordinates)

class Card:
    def __init__(self, num, title, tl, tr):
        self.inner = Image.new("RGB", (IW, IH), BG)
        self.d = ImageDraw.Draw(self.inner)
        d = self.d
        d.rectangle((0, 0, IW, 40), fill=NAVY); d.rectangle((0, 40, IW, 43), fill=ORG)
        d.text((10, 8), f"{num}  {title}", font=BT, fill=ORG)
        d.text((IW - 10, 14), f"{tl}   {tr}", font=F11, fill=(170, 175, 190), anchor="ra")
        self.y = 50
    def head(self, t, c="t"):
        d = self.d
        d.rectangle((0, self.y, 3, self.y + 13), fill=TAG); d.text((8, self.y), t, font=B10, fill=COL[c]); self.y += 18
    def band(self, t):
        self.d.rectangle((0, self.y, IW, self.y + 21), fill=BAND); self.d.text((8, self.y + 3), t, font=F13, fill=TXT); self.y += 24
    def kv(self, k, v, c="t"):
        self.d.text((2, self.y), k, font=F13, fill=TXT); self.d.text((VX, self.y), v, font=F13, fill=COL[c]); self.y += 18
    def nine(self, n, k, v):
        self.d.text((2, self.y + 2), n, font=F10, fill=GRY); self.d.text((20, self.y + 2), k, font=F10, fill=GRY)
        self.d.text((80, self.y), v, font=F13, fill=TXT); self.y += 17
    def line(self, t, c="t", f=None):
        self.d.text((2, self.y), t, font=f or F11, fill=COL[c]); self.y += 15
    def chrow(self, ch, fq, name, tag, note=""):
        d = self.d
        d.text((2, self.y + 2), ch, font=F11, fill=GRY); d.text((22, self.y), fq, font=F13, fill=TXT)
        d.text((140, self.y), name, font=F13, fill=GRN)
        if note: d.text((IW - 50, self.y + 2), note, font=F10, fill=GRY, anchor="ra")
        d.text((IW - 4, self.y + 2), tag, font=B11, fill=TAG, anchor="ra"); self.y += 18
    def rule(self):
        self.y += 3; self.d.line((0, self.y, IW, self.y), fill=RULE); self.y += 6
    def save(self, path):
        d = self.d
        d.line((0, IH - 22, IW, IH - 22), fill=RULE)
        d.text((2, IH - 16), "RESTRICTED   ·   FOR SIMULATION USE ONLY", font=F10, fill=GRY)
        out = Image.new("RGB", (W, H), BG); out.paste(self.inner, (MX, MY)); out.save(path)
        print("%-12s bottom y %d / %d" % (os.path.basename(path), self.y, IH - 24))

def admin():
    c = Card("01", "ADMIN", "CAS-1", "SYRIA")
    c.head("MISSION")
    c.kv("TYPE", "CAS  TYPE II  (Laser)"); c.kv("A/C", "F/A-18C  (single)")
    c.kv("CALLSIGN", "467 (ship)  /  HORNET 51 (tac)"); c.kv("MSN#", "4101 (JTAC-1) · 4102 (JTAC-2)")
    c.rule(); c.head("LOADOUT")
    c.kv("A/A", "2× AIM-120  ·  2× AIM-9X"); c.kv("A/G 1", "2× AGM-65E  (Pointer target)")
    c.kv("A/G 2", "4× GBU-12   (Eyeball target)"); c.kv("POD", "ATFLIR  (LST mode)")
    c.rule(); c.head("CARRIER  (CVN)")
    c.kv("TACAN", "72X  WSH"); c.kv("ICLS", "Ch 12  WSH"); c.kv("BRC", "355°M (live: Marshal call)")
    c.kv("CASE", "III dep → II rec  (flags 100/102)")
    c.rule(); c.head("IFF / MODES")
    c.kv("MODE 4", "Check-in on Strike freq", "o"); c.kv("SQUAWK", "2042")
    c.rule(); c.head("HARD DECK  /  RESTRICTIONS")
    c.kv("ENGAGE AREA", "23 000 ft MSL (JTAC-1/2)", "r"); c.kv("TRANSIT", "not in effect")
    c.kv("MANPADS inj", "threat call · deck unchanged", "o")
    c.rule(); c.head("LASER CODES")
    c.kv("POINTER 11", "1688", "y"); c.kv("EYEBALL 11", "1688", "y"); c.kv("65E code", "Set in cockpit → 1688", "o")
    return c

def comm():
    c = Card("02", "COMM LADDER", "CAS-1", "SYRIA")
    c.band("COMM 1  (UFC → C1)   all AM")
    for r in [("01","262.00 AM","TOWER/PADDLES","TWR","CASE I/II"),("02","269.00 AM","DEPARTURE","DEP",""),
              ("03","265.00 AM","STRIKE","STK",""),("04","333.30 AM","POINTER 11","JTAC-1",""),
              ("05","333.40 AM","EYEBALL 11","JTAC-2",""),("06","251.10 AM","OVERLORD","OVL",""),
              ("07","252.10 AM","TEXACO 11","TKR",""),("15","263.00 AM","APPROACH","APP","+CASE III LSO"),
              ("16","261.00 AM","MARSHAL","MRS","CV COMMS")]:
        c.chrow(*r)
    c.rule(); c.band("COMM 2  (UFC → C2)")
    c.chrow("01", "251.10 AM", "OVERLORD mon", "OVL")
    c.chrow("02", "128.10 AM", "AI traffic", "AI", "02–10: 128.1–128.9")
    c.rule(); c.head("DISCRETE / GUARD")
    c.kv("GUARD", "243.00 AM (monitor)", "m"); c.kv("ABORT (tac)", 'JTAC: "abort, abort, abort"')
    c.kv("CVN native", "127.60 AM not used (F1)", "m")
    c.rule(); c.head("COMM FLOW   (F10 CAS-1 COMMS / CV COMMS)")
    flow = [("1","Airborne","DEP","C1-02","CASE III dep (I/II zip)"),("2","7 DME/clrd","STK","C1-03","Mode 4 · Kilo"),
            ("3","Strike h/o","OVL","C1-06","check in · picture"),("4","20 NM to CP","PTR","C1-04","native JTAC"),
            ("5","Off Pointer","OVL","C1-06","→ EYE C1-05"),("6","Off Eyeball","OVL","C1-06","INFLTREP → Texaco"),
            ("7","Texaco","TKR","C1-07","check in · refuel"),("8","Off Texaco","OVL","C1-06","RTB · feet wet"),
            ("9","90 NM CVN","STK","C1-03","check in inbound"),("10","50 NM CVN","MRS","C1-16","check in · readback"),
            ("11","Marshal h/o","APP","C1-15","CASE II/III appr"),("12","See you at 10","TWR","C1-01","ZIPLIP (CASE I/II)")]
    for n, a, b, ch, e in flow:
        d = c.d; y = c.y
        d.text((2, y), n, font=F11, fill=TXT); d.text((22, y), a, font=F11, fill=TXT)
        d.text((122, y), "→", font=F11, fill=GRY); d.text((136, y), b, font=F11, fill=GRN)
        d.text((166, y), ch, font=F11, fill=GRN); d.text((214, y), e, font=F11, fill=TXT); c.y += 15
    c.rule(); c.head("CV HOLD")
    c.line("CASE II/III: R-196 / 25 DME / angels 10 · EAT")
    c.line("CASE I: overhead, angels 2 · commence at port beam")
    return c

def route():
    c = Card("03", "ROUTE / NAV", "CAS-1", "SYRIA")
    c.head("OUTBOUND  (CASE III DEP → 043°M → 233 NM)")
    d = c.d
    d.text((2, c.y), "WP", font=F10, fill=GRY); d.text((42, c.y), "NAME", font=F10, fill=GRY); d.text((190, c.y), "NOTES", font=F10, fill=GRY); c.y += 14
    wps = [("WP0","CATAPULT","t","CVN","CASE III dep"),("WP1","DEPART","t","","22 000 ft · alt hold"),
           ("WP2","CP TIGER","t","YE 1990 4989","22 000 ft · JTAC h/o 20 NM out"),
           ("IP1","IP LYNX","y","37S BV 8009 0816","24 000 ft · JTAC-1"),
           ("TGT1","TARGET ALPHA","r","BV 6187 2081","elev 570 ft"),
           ("IP2","IP PUMA","y","36S YE 4714 5182","24 000 ft · JTAC-2"),
           ("TGT2","TARGET BRAVO","r","YE 5987 3843","elev 150 ft")]
    for wp, name, col, grid, note in wps:
        y = c.y
        d.text((2, y + 1), wp, font=B10, fill=COL[col] if col != "t" else TXT)
        d.text((42, y), name, font=F13, fill=COL[col]); c.y += 15
        d.text((50, c.y), grid, font=F11, fill=TXT); d.text((190, c.y), note, font=F11, fill=GRY); c.y += 14
    c.rule(); c.head("TANKER / EGRESS")
    c.kv("TEXACO 11", "YE 0694 6582 · angels 15", "g"); c.kv("FREQ", "252.10 · btn 7 (COMM1-07)")
    c.kv("EGRESS", "Feet wet → RTB 043°M rev")
    c.rule(); c.head("RETURN CORRIDOR")
    c.kv("CORRIDOR", "050° radial ±15° (035–065)", "o"); c.kv("MARSHAL", "50 NM → COMM1-16 (261.00 AM)")
    c.kv("RECOVERY", "BRC 355° · CASE II (flag 102)")
    c.rule(); c.head("MAG VARIATION")
    c.kv("AREA", "True − 5°  →  Mag ≈ True+5°", "m")
    c.rule(); c.head("HARD DECK")
    c.kv("ENGAGE AREA", "23 000 ft MSL", "r"); c.kv("TRANSIT", "not in effect")
    return c

def jtac(num, name, tl, tr, contact, nine, restr, extra_head, extra, flow, threats=None, banner=None):
    c = Card(num, name, tl, tr)
    c.head("CONTACT")
    for k, v, col in contact: c.kv(k, v, col)
    c.rule(); c.head("9-LINE  (REFERENCE)")
    for i, (k, v) in enumerate(nine, 1): c.nine(str(i), k, v)
    c.rule(); c.head("RESTRICTIONS / GEOMETRY", "r")
    for k, v, col in restr: c.kv(k, v, col)
    if extra:
        c.rule(); c.head(extra_head)
        for a, b in extra:
            c.d.text((2, c.y + 1), a, font=B10, fill=GRY); c.d.text((40, c.y), b, font=F13, fill=TXT); c.y += 17
    c.rule(); c.head("BREVITY FLOW")
    for l in flow: c.line(l, f=F10)
    if threats:
        c.rule(); c.head("THREATS")
        for l, col in threats: c.line(l, col, F10)
    if banner:
        c.y += 2; c.d.rectangle((0, c.y, IW, c.y + 18), fill=(250, 232, 200))
        c.d.text((4, c.y + 3), banner, font=F10, fill=OCH); c.y += 20
    return c

def jtac1():
    return jtac("04", "POINTER 11", "JTAC-1", "ALPHA",
        [("CALLSIGN","POINTER ONE-ONE","t"),("FREQ","333.30 AM · COMM1-04","t"),("LASER","1688","y"),
         ("CHECK-IN","OVERLORD h/o, 20 NM to CP","t")],
        [("IP","LYNX"),("HDG","300°M"),("DIST","12.0 NM"),("ELEV","570 ft"),("TGT","SA-13 launcher + T-55 tank"),
         ("GRID","BV 6187 2081"),("MARK","Laser · Pointer · 1688"),("FRDLY","EAST · 1 200 m"),
         ("EGRESS","North → TIGER · block 24–26k")],
        [("FAH","285° – 315°  (attack cone)","r"),("HARD DECK","23 000 ft MSL (eng. area)","r"),
         ("LTL","260° (laser-target line)","t"),("TYPE","Type II · BOT","t")],
        None, None,
        ["IP inbound  →  Continue","In [hdg]  →  Cleared hot","Rifle  →  Ten seconds  →  Laser on",
         "JTAC: Lasing  →  Spot  →  [release]","Terminate  →  Laser off  ·  BDA"],
        threats=[("SA-13  at  BV62  (target site)", "r"), ("SA-8  vicinity  YE53  ·  2 NM", "o")])

def jtac2():
    return jtac("05", "EYEBALL 11", "JTAC-2", "BRAVO",
        [("CALLSIGN","EYEBALL ONE-ONE","t"),("FREQ","333.40 AM · COMM1-05","t"),("LASER","1688","y"),
         ("CHECK-IN","Via OVERLORD, off Pointer 11","t")],
        [("IP","PUMA"),("HDG","135°M"),("DIST","10.0 NM"),("ELEV","150 ft"),("TGT","SA-8 btry (2×TEL+BTR+T-72)"),
         ("GRID","YE 5987 3843"),("MARK","Laser · Eyeball · 1688"),("FRDLY","WEST · 400 m"),
         ("EGRESS","Left pull NW · feet wet")],
        [("FAH","135° – 145°  (tight cone)","r"),("HARD DECK","23 000 ft MSL (eng. area)","r"),
         ("LTL","105° (laser-target line)","t"),("TYPE","Type II · BOT","t")],
        "TARGET ORDER  (4 RUNS)",
        [("1st","Northern SA-8 launcher"),("2nd","Southern SA-8 launcher"),("3rd","BTR (~150 m NE of 2nd)"),
         ("4th","T-72 (~250 m NW of BTR)")],
        ["IP inbound  →  Continue","In [hdg]  →  Cleared hot  →  Bomb away","Ten seconds  →  Laser on  →  Lasing",
         "Terminate  →  Laser off  ·  BDA"],
        banner="! MANPADS inject (25%): threat call · deck 23 000 MSL")

if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "src", "KNEEBOARD", "images")
    for fn, mk in [("01_ADMIN.png", admin), ("02_COMM.png", comm), ("03_ROUTE.png", route),
                   ("04_JTAC1.png", jtac1), ("05_JTAC2.png", jtac2)]:
        mk().save(os.path.join(out, fn))
