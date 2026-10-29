# make_test_variant.py | v1.0.0
# Builds air-start TEST copies of a CAS mission so a JTAC change can be flown in minutes instead of
# an hour. The source .miz is read only; each variant is written NEXT TO it (Missions folder) as
#   "<name> TEST-J1.miz"  hero 30 NM before CP TIGER on the departure->CP leg, heading to CP
#   "<name> TEST-J2.miz"  hero over CP TIGER, heading to the JTAC-2 target group (Eyeball 11)
# Never writes inside the repo (.miz files stay out of git).
#
#   python tools/make_test_variant.py "<...>/Close Air Support (L).miz" --start J1 J2
#          [--alt-ft 24000] [--kt 410] [--nm 30] [--group CAS-1] [--unit Player_01]
#          [--cp-name "Contact JTAC"] [--j2-target "SAM YE53 (SA-8)-1"]
#
# Changes, hero group only: first route point becomes an air start "Turning Point" named
# "AIRSTART J1" / "AIRSTART J2" (Comms_Director >= v1.6.1 reads this tag and skips the carrier
# legs), the carrier take-off fields (linkUnit / helipadId / airdromeId / parking) are removed, the
# departure point between the start and the CP is dropped, unit position / altitude / heading /
# speed are set. Payload and fuel are not touched. Everything else in the .miz is copied unchanged.
# Heading convention (ME unit table): heading = radians clockwise from north, psi = -heading [V].

import argparse
import copy
import io
import math
import os
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, ".."))
sys.path.insert(0, REPO)
import dcslua  # noqa: E402


def s(v):
    return v.decode("utf-8", "replace") if isinstance(v, bytes) else v


def find_group(mission, cat, name):
    for side in mission[b"coalition"].values():
        for c in side.get(b"country", {}).values():
            for g in c.get(cat, {}).get(b"group", {}).values():
                if s(g.get(b"name")) == name:
                    return g
    return None


def build(mission, a, key):
    g = find_group(mission, b"plane", a.group)
    if g is None:
        sys.exit("plane group not found: " + a.group)
    unit = next((u for u in g[b"units"].values() if s(u.get(b"name")) == a.unit), None)
    if unit is None:
        sys.exit("unit not found in %s: %s" % (a.group, a.unit))
    pts = [p for _, p in sorted(g[b"route"][b"points"].items())]
    cp_i = next((i for i, p in enumerate(pts) if s(p.get(b"name", b"")) == a.cp_name), None)
    if cp_i is None or cp_i < 1:
        sys.exit("route point '%s' not found (or it is the first point)" % a.cp_name)
    cp = pts[cp_i]
    cx, cy = cp[b"x"], cp[b"y"]
    if key == "J1":
        prev = pts[cp_i - 1]
        dx, dy = cx - prev[b"x"], cy - prev[b"y"]
        d = math.hypot(dx, dy)
        ux, uy = dx / d, dy / d
        sx, sy = cx - ux * a.nm * 1852, cy - uy * a.nm * 1852
        hdg = math.atan2(uy, ux)
    else:
        tg = find_group(mission, b"vehicle", a.j2_target)
        if tg is None:
            sys.exit("vehicle group not found: " + a.j2_target)
        us = list(tg[b"units"].values())
        tx = sum(u[b"x"] for u in us) / len(us)
        ty = sum(u[b"y"] for u in us) / len(us)
        sx, sy = cx, cy
        hdg = math.atan2(ty - cy, tx - cx)
        print("  J2 target %s: %.1f NM from CP" % (a.j2_target, math.hypot(tx - cx, ty - cy) / 1852))
    hdg %= 2 * math.pi
    alt = a.alt_ft * 0.3048
    spd = a.kt * 0.514444
    for k in (b"parking", b"parking_id", b"parking_landing", b"parking_landing_id"):
        unit.pop(k, None)
    unit.update({b"x": sx, b"y": sy, b"alt": alt, b"alt_type": b"BARO", b"heading": hdg, b"psi": -hdg,
                 b"speed": spd})
    g[b"x"], g[b"y"] = sx, sy
    p1 = pts[0]
    for k in (b"linkUnit", b"helipadId", b"airdromeId", b"linkOffset"):
        p1.pop(k, None)
    p1.update({b"x": sx, b"y": sy, b"alt": alt, b"alt_type": b"BARO", b"type": b"Turning Point",
               b"action": b"Turning Point", b"speed": spd, b"ETA": 0, b"ETA_locked": True,
               b"name": ("AIRSTART " + key).encode()})
    keep = [p1] + pts[cp_i:]          # drop the departure point(s) before the CP
    g[b"route"][b"points"] = {i: p for i, p in enumerate(keep, 1)}
    print("  %s: start %.0f / %.0f (ME x / y), heading %03.0f true, %d ft, %d kt, route %d point(s)"
          % (key, sx, sy, math.degrees(hdg), a.alt_ft, a.kt, len(keep)))


def main():
    ap = argparse.ArgumentParser(description="air-start TEST variants of a CAS .miz (written next to it)")
    ap.add_argument("miz")
    ap.add_argument("--start", nargs="+", choices=["J1", "J2"], default=["J1", "J2"])
    ap.add_argument("--alt-ft", type=int, default=24000)
    ap.add_argument("--kt", type=int, default=410)
    ap.add_argument("--nm", type=float, default=30)
    ap.add_argument("--group", default="CAS-1")
    ap.add_argument("--unit", default="Player_01")
    ap.add_argument("--cp-name", default="Contact JTAC")
    ap.add_argument("--j2-target", default="SAM YE53 (SA-8)-1")
    a = ap.parse_args()
    src = os.path.abspath(a.miz)
    if src.startswith(REPO + os.sep):
        sys.exit("refusing: source/variants must not live inside the repo")
    stem = os.path.splitext(os.path.basename(src))[0]
    with zipfile.ZipFile(src) as zin:
        raw = zin.read("mission")
        for key in a.start:
            _, mission = dcslua.parse(raw)
            print(stem, "->", key)
            build(mission, a, key)
            out = os.path.join(os.path.dirname(src), "%s TEST-%s.miz" % (stem, key))
            buf = io.BytesIO()
            with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zout:
                for info in zin.infolist():
                    if info.filename == "mission":
                        continue
                    # copy: writestr() rewrites header_offset on the ZipInfo it gets
                    zout.writestr(copy.copy(info), zin.read(info.filename))
                zout.writestr("mission", dcslua.dump("mission", mission))
            with open(out, "wb") as f:
                f.write(buf.getvalue())
            with zipfile.ZipFile(out) as t:
                if t.testzip():
                    sys.exit("zip test failed: " + out)
            print("  written", out, os.path.getsize(out), "bytes")


if __name__ == "__main__":
    main()
