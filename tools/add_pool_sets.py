# add_pool_sets.py | v1.0.0
# CAS-1 target pool, first batch (decisions Onur 2026-11-04 03:28: ME late-activated groups, placed by tool,
# sets B + C per JTAC; plan claude/target-pool-tasking-pack-plan-2026-11-04.md). Writes four late-activated RED
# vehicle groups into src/mission, in the country of each JTAC's existing set A (Syria), with set A's route task
# (Hold + the same ROE / option wrapped actions). Idempotent: an existing group of that name is replaced by the
# computed one, so a second run reports "no change".
#
#   python tools/add_pool_sets.py [--dry-run]      then: python tools/sync_missions.py
#
# Weapons budget (2x AGM-65E for Pointer, 4x GBU-12 for Eyeball; kneeboard 01 / 04 / 05): every Pointer set has
# 2 units, every Eyeball set 4, like set A. Positions are offsets from set A's group centre, on the side away from
# the friendlies (Bravo 2-1 is spawned at bearing 200 from the target): the terrain under them is NOT known
# offline - the DCS audit run (Tasking_Pick site check: surface, slope, scenery) decides whether a set stays.
# Units face 200 deg true (toward the friendlies). Unit types are ones the template already uses.
# Names avoid the SAM / EW prefixes (Skynet would take them into the IADS).

import argparse
import copy
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, ".."))
sys.path.insert(0, REPO)
import dcslua  # noqa: E402

MISSION = os.path.join(REPO, "src", "mission")
FACE = 200.0                       # deg true, toward the friendlies

# name, set A group (centre / country / route task template), offset bearing (deg true), offset m,
# formation: list of (forward m, right m, type)
SETS = [
    ("CAS J1-B (Armor)-1", "SAM BV51 (SA-13)-1", 20, 1600,
     [(0, -25, "T-72B"), (0, 25, "BMP-1")]),
    ("CAS J1-C (Battery)-1", "SAM BV51 (SA-13)-1", 45, 3200,
     [(0, -30, "SAU Gvozdika"), (0, 30, "SAU Gvozdika")]),
    ("CAS J2-B (Armor)-1", "SAM YE53 (SA-8)-1", 10, 1500,
     [(0, 0, "T-72B"), (-40, -40, "T-72B"), (-40, 40, "T-72B"), (-80, 0, "BMP-1")]),
    ("CAS J2-C (Battery)-1", "SAM YE53 (SA-8)-1", 40, 3000,
     [(0, -75, "SAU Gvozdika"), (0, -25, "SAU Gvozdika"), (0, 25, "SAU Gvozdika"), (0, 75, "SAU Gvozdika")]),
]


def r6(v):
    return round(v, 6)


def find_group(m, name):
    for side, cs in m[b"coalition"].items():
        for c in (cs.get(b"country") or {}).values():
            for cat in (b"plane", b"helicopter", b"vehicle", b"ship", b"static"):
                gt = (c.get(cat) or {}).get(b"group") or {}
                for gi, g in gt.items():
                    if g[b"name"] == name:
                        return side, c, cat, gt, gi, g
    return None


def max_ids(m):
    gm = um = 0
    for cs in m[b"coalition"].values():
        for c in (cs.get(b"country") or {}).values():
            for cat in (b"plane", b"helicopter", b"vehicle", b"ship", b"static"):
                for g in ((c.get(cat) or {}).get(b"group") or {}).values():
                    gm = max(gm, int(g[b"groupId"]))
                    for u in g[b"units"].values():
                        um = max(um, int(u[b"unitId"]))
    return gm, um


def build(m, name, base_name, brg, dist, form, ids):
    base = find_group(m, base_name.encode())
    if not base:
        sys.exit("set A group %s not in src/mission" % base_name)
    _, c, _, _, _, bg = base
    a = math.radians(brg)
    cx, cy = bg[b"x"] + dist * math.cos(a), bg[b"y"] + dist * math.sin(a)
    f, rgt = math.radians(FACE), math.radians(FACE + 90)
    g = copy.deepcopy(bg)
    gid, uid0 = ids
    g[b"name"] = name.encode()
    g[b"groupId"] = gid
    g[b"lateActivation"] = True
    g[b"x"], g[b"y"] = r6(cx), r6(cy)
    pt = g[b"route"][b"points"][1]
    pt[b"x"], pt[b"y"] = r6(cx), r6(cy)
    g[b"route"][b"points"] = {1: pt}
    g[b"route"][b"spans"] = {1: {1: {b"x": r6(cx), b"y": r6(cy)}, 2: {b"x": r6(cx), b"y": r6(cy)}}}
    proto = bg[b"units"][1]
    units = {}
    for i, (fwd, right, typ) in enumerate(form, 1):
        u = copy.deepcopy(proto)
        u[b"name"] = ("%s-%d" % (name, i)).encode()
        u[b"unitId"] = uid0 + i - 1
        u[b"type"] = typ.encode()
        u[b"x"] = r6(cx + fwd * math.cos(f) + right * math.cos(rgt))
        u[b"y"] = r6(cy + fwd * math.sin(f) + right * math.sin(rgt))
        u[b"heading"] = r6(f)
        u[b"playerCanDrive"] = False
        u[b"skill"] = b"Average"
        units[i] = u
    g[b"units"] = units
    return c, g


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    with open(MISSION, "rb") as fh:
        vname, m = dcslua.parse(fh.read())
    changes = []
    for name, base_name, brg, dist, form in SETS:
        old = find_group(m, name.encode())
        if old:
            _, c, _, gt, gi, og = old
            ids = (og[b"groupId"], min(u[b"unitId"] for u in og[b"units"].values()))
            if len(og[b"units"]) != len(form):
                ids = (og[b"groupId"], max_ids(m)[1] + 1)
        else:
            gm, um = max_ids(m)
            ids = (gm + 1, um + 1)
        c, g = build(m, name, base_name, brg, dist, form, ids)
        if old:
            if dcslua.dump("x", {1: og}) == dcslua.dump("x", {1: g}):
                continue
            gt[gi] = g
            changes.append("%s updated (groupId %d)" % (name, g[b"groupId"]))
        else:
            veh = c.setdefault(b"vehicle", {}).setdefault(b"group", {})
            veh[max(veh) + 1 if veh else 1] = g
            changes.append("%s added (groupId %d, units %d-%d, %s, x %.0f y %.0f)" % (
                name, g[b"groupId"], ids[1], ids[1] + len(form) - 1, c[b"name"].decode(), g[b"x"], g[b"y"]))
    for ch in changes:
        print("  " + ch)
    if not changes:
        print("src/mission: no change")
        return 0
    if a.dry_run:
        print("dry run: not written")
        return 0
    with open(MISSION, "wb") as fh:
        fh.write(dcslua.dump(vname, m))
    print("written: src/mission (%d change(s)); next: python tools/sync_missions.py" % len(changes))
    return 0


if __name__ == "__main__":
    sys.exit(main())
