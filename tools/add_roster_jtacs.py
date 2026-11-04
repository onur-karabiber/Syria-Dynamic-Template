# add_roster_jtacs.py | v1.0.0
# P3 of the JTAC roster plan (claude/jtac-roster-effects-plan-2026-11-04.md, decisions Onur 2026-11-04 12:41):
# makes JTAC-8 (AXEMAN 11, CAS_PACK J3) and FAC-1 (DARKNIGHT 11, CAS_PACK J4) scripted JTACs in src/mission.
# Idempotent (a second run reports "no change"):
#   * Player_01 COMM1 presets: 10 = 333.50 (AXEMAN 11, the native JTAC-8 frequency), 12 = 333.10 (DARKNIGHT 11, the
#     native FAC-1 frequency), 13 = 256.00 / 14 = 258.00 (their alternates). Onur 11:30: 10 / 12 / 13 / 14 unused.
#   * CAS-1 route: "IP JACKAL" (12 NM / 330 deg true from BASE YE55, over the sea NW of the target, 6.9 NM outside
#     every other SAM ring) and "IP COBRA" (12 NM north of SAM BV53) appended after IP PUMA, PUMA's altitude / speed.
#   * JTAC-4: DARKNIGHT 11's ground team (new BLUE group, copy of JTAC-1: Stryker, invisible, immortal), 5 km at
#     230 deg true from SAM BV53 (behind the friendlies; the MQ-9 FAC-1 is the designator and the eye, so this
#     team does not need line of sight - CAS_PACK J4 op.auto = false). SetFrequency 333.10, SetCallsign Darknight 1.
#   * JTAC-8: SetCallsign Axeman 1 (was Whiplash 1); native FAC tasks of JTAC-8 and FAC-1 removed
#     (tools/strip_native_jtac.py v1.1.0 logic: FAC, FAC_AttackGroup, FAC_EngageGroup, FAC_AttackUnit). FAC-1 keeps
#     its Orbit, invisible, immortal.
#   python tools/add_roster_jtacs.py [--dry-run]     then: python tools/add_pool_sets.py; python tools/sync_missions.py

import argparse
import copy
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, ".."))
sys.path.insert(0, REPO)
sys.path.insert(0, HERE)
import dcslua  # noqa: E402
from add_pool_sets import find_group, max_ids, r6  # noqa: E402
from strip_native_jtac import strip  # noqa: E402

MISSION = os.path.join(REPO, "src", "mission")
PRESETS = {10: 333.5, 12: 333.1, 13: 256.0, 14: 258.0}
IPS = [("IP JACKAL", 91114.0, -19480.0), ("IP COBRA", 82158.0, 39005.0)]
JT4 = {"name": "JTAC-4", "from": "JTAC-1", "target": "SAM BV53 (SA-13)-1", "brg": 230, "m": 5000,
       "freq": 333100000, "callname": 2}       # DCS JTAC call names: 1 Axeman, 2 Darknight, ... 7 Whiplash
JT3_CALLNAME = 1


def tasks_of(g):
    return g[b"route"][b"points"][1][b"task"][b"params"][b"tasks"]


def wrapped(tasks, aid):
    for _, t in sorted(tasks.items()):
        if t.get(b"id") == b"WrappedAction" and t[b"params"][b"action"].get(b"id") == aid:
            return t
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    with open(MISSION, "rb") as fh:
        vname, m = dcslua.parse(fh.read())
    before = dcslua.dump(vname, m)
    log = []

    # presets
    _, _, _, _, _, cas = find_group(m, b"CAS-1")
    hero = next(u for u in cas[b"units"].values() if u[b"name"] == b"Player_01")
    ch = hero[b"Radio"][1][b"channels"]
    for btn, f in PRESETS.items():
        if abs(float(ch[btn]) - f) > 1e-6:
            log.append("Player_01 COMM1 preset %d: %s -> %.2f" % (btn, ch[btn], f))
            ch[btn] = f

    # IP route points
    pts = cas[b"route"][b"points"]
    names = {p.get(b"name"): i for i, p in pts.items()}
    puma = pts[names[b"IP PUMA"]]
    for nm, x, y in IPS:
        if nm.encode() in names:
            p = pts[names[nm.encode()]]
            if (p[b"x"], p[b"y"]) != (x, y):
                p[b"x"], p[b"y"] = x, y
                log.append("CAS-1 %s moved to x %.0f y %.0f" % (nm, x, y))
            continue
        p = copy.deepcopy(puma)
        p[b"name"], p[b"x"], p[b"y"] = nm.encode(), x, y
        p.pop(b"ETA", None)
        p[b"ETA_locked"] = False
        i = max(pts) + 1
        pts[i] = p
        names[nm.encode()] = i
        log.append("CAS-1 route point %d %s (x %.0f y %.0f)" % (i, nm, x, y))

    # JTAC-4 ground team
    tgt = find_group(m, JT4["target"].encode())[5]
    r = math.radians(JT4["brg"])
    x, y = r6(tgt[b"x"] + JT4["m"] * math.cos(r)), r6(tgt[b"y"] + JT4["m"] * math.sin(r))
    old = find_group(m, JT4["name"].encode())
    if not old:
        side, c, cat, gt, gi, src = find_group(m, JT4["from"].encode())
        g = copy.deepcopy(src)
        gm, um = max_ids(m)
        g[b"name"], g[b"groupId"] = JT4["name"].encode(), gm + 1
        u = g[b"units"][1]
        u[b"name"], u[b"unitId"] = (JT4["name"] + "-1").encode(), um + 1
        gt[max(gt) + 1] = g
        log.append("JTAC-4 added (groupId %d, unitId %d)" % (gm + 1, um + 1))
    else:
        g = old[5]
    u = g[b"units"][1]
    if (g[b"x"], g[b"y"]) != (x, y):
        g[b"x"], g[b"y"], u[b"x"], u[b"y"] = x, y, x, y
        pt = g[b"route"][b"points"][1]
        pt[b"x"], pt[b"y"] = x, y
        log.append("JTAC-4 at x %.0f y %.0f (%d m / %d deg from %s)" % (x, y, JT4["m"], JT4["brg"], JT4["target"]))
    tk = tasks_of(g)
    for _, t in list(tk.items()):
        if t.get(b"id") == b"WrappedAction" and t[b"params"][b"action"].get(b"id") == b"EPLRS":
            log.append("JTAC-4: EPLRS removed (copied from JTAC-1)")
    keep = [t for _, t in sorted(tk.items())
            if not (t.get(b"id") == b"WrappedAction" and t[b"params"][b"action"].get(b"id") == b"EPLRS")]
    if len(keep) != len(tk):
        tk.clear()
        for i, t in enumerate(keep, 1):
            t[b"number"] = i
            tk[i] = t
    sf = wrapped(tk, b"SetFrequency")
    if sf and sf[b"params"][b"action"][b"params"][b"frequency"] != JT4["freq"]:
        sf[b"params"][b"action"][b"params"][b"frequency"] = JT4["freq"]
        log.append("JTAC-4 SetFrequency %.2f" % (JT4["freq"] / 1e6))
    sc = wrapped(tk, b"SetCallsign")
    if sc and sc[b"params"][b"action"][b"params"][b"callname"] != JT4["callname"]:
        sc[b"params"][b"action"][b"params"][b"callname"] = JT4["callname"]
        log.append("JTAC-4 SetCallsign Darknight 1")

    # JTAC-8 call sign, native FAC tasks
    j8 = find_group(m, b"JTAC-8")[5]
    sc = wrapped(tasks_of(j8), b"SetCallsign")
    if sc and sc[b"params"][b"action"][b"params"][b"callname"] != JT3_CALLNAME:
        sc[b"params"][b"action"][b"params"][b"callname"] = JT3_CALLNAME
        log.append("JTAC-8 SetCallsign Axeman 1")
    n = strip(m, ["JTAC-8", "FAC-1"])
    if n:
        log.append("native FAC tasks removed: %d" % n)

    for line in log:
        print("  " + line)
    after = dcslua.dump(vname, m)
    if after == before:
        print("src/mission: no change")
        return 0
    if a.dry_run:
        print("dry run: not written")
        return 0
    with open(MISSION, "wb") as fh:
        fh.write(after)
    print("written: src/mission; next: python tools/add_pool_sets.py, python tools/sync_missions.py")
    return 0


if __name__ == "__main__":
    sys.exit(main())
