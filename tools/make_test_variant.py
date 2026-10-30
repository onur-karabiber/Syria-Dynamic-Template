# make_test_variant.py | v1.2.0
# v1.2.0: --start AAR / AAR-S (AAR test flight, project doc claude/aar-test-flight-2026-10-30.md):
#         hero --aar-nm (12) NM BEHIND the tanker group's first point on the tanker's unit heading,
#         same heading, --aar-alt-ft (20000) ft, --aar-kt (410 = ME speed, ~300 KIAS at FL200),
#         internal fuel --aar-internal-lb (5770 lb; + full FPU-8A ~2230 = ~8000 lb), first point
#         "AIRSTART AAR", route continues from the CP. tools/aar_test_logger.lua is injected as a
#         triggerOnce DO SCRIPT ([AAR-TEST] log lines); AAR-S also sets AI SILENCE on the tanker.
# v1.1.0: random RED air activations are switched off in the TEST variants (every trigger action
#         a_activate_group for a late-activated RED plane / helicopter group is removed from
#         trigrules and from the compiled trig.actions); --keep-red-air keeps them. The source
#         mission (CAS (L)) keeps them in any case. (Flight 2026-10-29: a MiG-23 ended a JTAC test.)
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
import re
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


def strip_red_air(mission):
    red = {}
    side = mission[b"coalition"].get(b"red", {})
    for c in side.get(b"country", {}).values():
        for cat in (b"plane", b"helicopter"):
            for g in c.get(cat, {}).get(b"group", {}).values():
                if g.get(b"lateActivation"):
                    red[g[b"groupId"]] = s(g[b"name"])
    rules, trig = mission.get(b"trigrules", {}), mission.get(b"trig", {})
    gone = []
    for k, r in rules.items():
        acts = r.get(b"actions", {})
        hit = [a for a in acts.values() if a.get(b"predicate") == b"a_activate_group" and a.get(b"group") in red]
        if not hit:
            continue
        keep = [a for _, a in sorted(acts.items()) if a not in hit]
        r[b"actions"] = {i: a for i, a in enumerate(keep, 1)}
        code = trig.get(b"actions", {}).get(k)
        if isinstance(code, bytes):
            for a in hit:
                code = re.sub(rb"a_activate_group\(%d\);\s*" % a[b"group"], b"", code)
            trig[b"actions"][k] = code
        gone += [red[a[b"group"]] for a in hit]
    print("  red air activations removed (%d): %s" % (len(gone), ", ".join(gone) or "none"))


def lua_str(b):
    """bytes -> body of a double-quoted Lua string literal."""
    return b.replace(b"\\", b"\\\\").replace(b'"', b'\\"').replace(b"\r", b"").replace(b"\n", b"\\n")


def add_do_script(mission, text, comment):
    """Appends a triggerOnce rule (condition: none) with one DO SCRIPT action, in both the editor
    rules (trigrules) and the compiled trig table, the way the ME writes 'SetSuperCarrier'."""
    rules, trig = mission[b"trigrules"], mission[b"trig"]
    n = max(list(rules.keys()) + list(trig[b"actions"].keys())) + 1
    rules[n] = {b"actions": {1: {b"predicate": b"a_do_script", b"text": text}},
                b"colorItem": b"0x00ff00ff", b"comment": comment.encode(), b"eventlist": b"",
                b"predicate": b"triggerOnce", b"rules": {}}
    trig[b"actions"][n] = b'a_do_script("' + lua_str(text) + b'"); mission.trig.func[%d]=nil;' % n
    trig[b"conditions"][n] = b"return(true)"
    trig[b"flag"][n] = True
    trig[b"func"][n] = b"if mission.trig.conditions[%d]() then mission.trig.actions[%d]() end" % (n, n)
    print("  trigger %d '%s' added (DO SCRIPT, %d bytes)" % (n, comment, len(text)))


def build_aar(mission, a, key):
    g = find_group(mission, b"plane", a.group)
    tk = find_group(mission, b"plane", a.tanker_group)
    if g is None or tk is None:
        sys.exit("group not found: %s / %s" % (a.group, a.tanker_group))
    unit = next((u for u in g[b"units"].values() if s(u.get(b"name")) == a.unit), None)
    if unit is None:
        sys.exit("unit not found in %s: %s" % (a.group, a.unit))
    pts = [p for _, p in sorted(g[b"route"][b"points"].items())]
    cp_i = next((i for i, p in enumerate(pts) if s(p.get(b"name", b"")) == a.cp_name), None)
    if cp_i is None or cp_i < 1:
        sys.exit("route point '%s' not found (or it is the first point)" % a.cp_name)
    t1 = tk[b"route"][b"points"][1]
    hdg = float(next(iter(tk[b"units"].values())).get(b"heading", 0.0)) % (2 * math.pi)
    sx = t1[b"x"] - math.cos(hdg) * a.aar_nm * 1852
    sy = t1[b"y"] - math.sin(hdg) * a.aar_nm * 1852
    alt, spd = a.aar_alt_ft * 0.3048, a.aar_kt * 0.514444
    for k in (b"parking", b"parking_id", b"parking_landing", b"parking_landing_id"):
        unit.pop(k, None)
    unit.update({b"x": sx, b"y": sy, b"alt": alt, b"alt_type": b"BARO", b"heading": hdg, b"psi": -hdg,
                 b"speed": spd})
    unit[b"payload"][b"fuel"] = round(a.aar_internal_lb / 2.20462, 1)
    g[b"x"], g[b"y"] = sx, sy
    p1 = pts[0]
    for k in (b"linkUnit", b"helipadId", b"airdromeId", b"linkOffset"):
        p1.pop(k, None)
    p1.update({b"x": sx, b"y": sy, b"alt": alt, b"alt_type": b"BARO", b"type": b"Turning Point",
               b"action": b"Turning Point", b"speed": spd, b"ETA": 0, b"ETA_locked": True,
               b"name": b"AIRSTART AAR"})
    keep = [p1] + pts[cp_i:]
    g[b"route"][b"points"] = {i: p for i, p in enumerate(keep, 1)}
    with open(os.path.join(HERE, "aar_test_logger.lua"), "rb") as f:
        logger = f.read().replace(b"__SILENCE__", b"true" if key == "AAR-S" else b"false")
    add_do_script(mission, logger, "AAR TEST LOGGER" + (" + TANKER SILENCE" if key == "AAR-S" else ""))
    print("  %s: start %.0f / %.0f (ME x / y), %.1f NM behind %s, heading %03.0f true, %d ft, ME speed %d kt, "
          "internal fuel %d lb" % (key, sx, sy, a.aar_nm, a.tanker_group, math.degrees(hdg), a.aar_alt_ft,
                                   a.aar_kt, a.aar_internal_lb))


def build(mission, a, key):
    if key.startswith("AAR"):
        return build_aar(mission, a, key)
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
    ap.add_argument("--start", nargs="+", choices=["J1", "J2", "AAR", "AAR-S"], default=["J1", "J2"])
    ap.add_argument("--tanker-group", default="TANKER-1")
    ap.add_argument("--aar-nm", type=float, default=12)
    ap.add_argument("--aar-alt-ft", type=int, default=20000)
    ap.add_argument("--aar-kt", type=int, default=410)
    ap.add_argument("--aar-internal-lb", type=int, default=5770)
    ap.add_argument("--alt-ft", type=int, default=24000)
    ap.add_argument("--kt", type=int, default=410)
    ap.add_argument("--nm", type=float, default=30)
    ap.add_argument("--group", default="CAS-1")
    ap.add_argument("--unit", default="Player_01")
    ap.add_argument("--cp-name", default="Contact JTAC")
    ap.add_argument("--j2-target", default="SAM YE53 (SA-8)-1")
    ap.add_argument("--keep-red-air", action="store_true", help="keep the random RED air activations")
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
            if not a.keep_red_air:
                strip_red_air(mission)
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
