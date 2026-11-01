# add_elint.py | v1.0.0
# Writes a COPY of a .miz with Hound ELINT wired in; the source .miz is not touched.
#   python tools/add_elint.py "<...>/Close Air Support (L).miz" "<...>/Close Air Support (L) HOUND.miz"
# What the copy gets:
#   * two "Do Script File" actions at the end of the mission-start trigger that loads Core_Scoring.lua:
#     HoundElint_0.5.2.lua, then Elint_Init.lua (files from scripts/ into l10n/DEFAULT/, keys in
#     mapResource, actions in both trigrules and the compiled trig string) - same mechanism as add_script.py
#   * BLUE static towers ELINT_TWR_1 / ELINT_TWR_2 (TOWERS below) in the first BLUE country listed
#     (TOWER_COUNTRY), unless a unit with that name already exists
# Refuses when the destination exists or a script is already referenced.
# Tower positions are provisional (2026-11-01): KELDAG = Jebel Aqra summit, KILIS = plateau north of
# Aleppo. Check the [ELINT] AUDIT lines in dcs.log, then move the statics in the ME.

import argparse
import os
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, ".."))
sys.path.insert(0, REPO)
sys.path.insert(0, HERE)
import dcslua  # noqa: E402
from add_script import add  # noqa: E402

SCRIPTS = ["HoundElint_0.5.2.lua", "Elint_Init.lua"]   # load order
TOWER_TYPE, TOWER_SHAPE = b"TV tower", b"tele_bash"     # as written by the ME (BASE-HS34_TV_tower-1)
TOWER_COUNTRY = b"Turkey"
# DCS x (north) / y (east) on the Syria map, from lat/lon with the map's transverse Mercator
# (lon0 39, k 0.9996, x0 282801.00000003993, y0 -3879865.9999999935)
TOWERS = [
    (b"ELINT_TWR_1", 103061.2, 9438.6),     # 35.9525 N 35.9692 E  Jebel Aqra / Keldag
    (b"ELINT_TWR_2", 188992.3, 111400.1),   # 36.7500 N 37.0800 E  Kilis plateau
]


def walk_ids(mission):
    gmax = umax = 0
    names = set()
    for side in mission[b"coalition"].values():
        for ctry in (side.get(b"country") or {}).values():
            for cat in (b"plane", b"helicopter", b"vehicle", b"ship", b"static"):
                for g in ((ctry.get(cat) or {}).get(b"group") or {}).values():
                    gmax = max(gmax, int(g.get(b"groupId", 0)))
                    for u in (g.get(b"units") or {}).values():
                        umax = max(umax, int(u.get(b"unitId", 0)))
                        if isinstance(u.get(b"name"), bytes):
                            names.add(u[b"name"])
    return gmax, umax, names


def add_towers(mission):
    blue = mission[b"coalition"][b"blue"][b"country"]
    ctry = next((c for c in blue.values() if c.get(b"name") == TOWER_COUNTRY), None)
    if ctry is None:
        sys.exit("BLUE country %s not in mission" % TOWER_COUNTRY.decode())
    gmax, umax, names = walk_ids(mission)
    groups = ctry.setdefault(b"static", {}).setdefault(b"group", {})
    for name, x, y in TOWERS:
        if name in names:
            print("tower %s already in mission - kept" % name.decode())
            continue
        gmax += 1
        umax += 1
        groups[(max(groups) if groups else 0) + 1] = {
            b"dead": False,
            b"groupId": gmax,
            b"heading": 0,
            b"hidden": False,
            b"name": name,
            b"route": {b"points": {1: {b"action": b"", b"alt": 0, b"formation_template": b"", b"name": b"",
                                       b"speed": 0, b"type": b"", b"x": x, b"y": y}}},
            b"units": {1: {b"category": b"Fortifications", b"heading": 0, b"name": name, b"rate": 100,
                           b"shape_name": TOWER_SHAPE, b"tasks": {}, b"type": TOWER_TYPE,
                           b"unitId": umax, b"x": x, b"y": y}},
            b"x": x,
            b"y": y,
        }
        print("tower %s (%s, %s) x=%.1f y=%.1f groupId %d unitId %d" % (
            name.decode(), TOWER_TYPE.decode(), TOWER_COUNTRY.decode(), x, y, gmax, umax))


def main():
    ap = argparse.ArgumentParser(description="write a copy of a .miz with Hound ELINT wired in")
    ap.add_argument("src", help="source .miz (not modified)")
    ap.add_argument("dst", help="destination .miz (must not exist)")
    a = ap.parse_args()
    if os.path.exists(a.dst):
        sys.exit("destination exists: " + a.dst)
    for s in SCRIPTS:
        if not os.path.isfile(os.path.join(REPO, "scripts", s)):
            sys.exit("not in scripts/: " + s)
    zin = zipfile.ZipFile(a.src)
    names = zin.namelist()
    _, mission = dcslua.parse(zin.read("mission"))
    _, mapres = dcslua.parse(zin.read("l10n/DEFAULT/mapResource"))
    for s in SCRIPTS:
        add(mission, mapres, s)
    add_towers(mission)
    skip = {"mission", "l10n/DEFAULT/mapResource"} | {"l10n/DEFAULT/" + s for s in SCRIPTS}
    tmp = a.dst + ".part"
    with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as zout:
        for nm in names:
            if nm in skip:
                continue
            zout.writestr(zin.getinfo(nm), zin.read(nm))
        zout.writestr("mission", dcslua.dump("mission", mission))
        zout.writestr("l10n/DEFAULT/mapResource", dcslua.dump("mapResource", mapres))
        for s in SCRIPTS:
            zout.write(os.path.join(REPO, "scripts", s), "l10n/DEFAULT/" + s)
    zin.close()
    os.replace(tmp, a.dst)
    print("written", a.dst, os.path.getsize(a.dst), "bytes")


if __name__ == "__main__":
    main()
