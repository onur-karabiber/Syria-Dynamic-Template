# patch_aar_me.py | v1.0.0
# Mission Editor changes from the AAR plan (project doc claude/aar-plan-2026-10-30.md,
# sections 12 and 16). Idempotent: a second run reports "no change".
#
#   1. TANKER-1 (Texaco 11, KC130): Circle orbit -> Race-Track anchor.
#      WP1 = anchor / ARCP (position unchanged), WP2 = 25 NM at 225 deg true, so the
#      refuelling (inbound) leg points at the carrier. DCS flies a Race-Track between
#      the orbit waypoint and the NEXT waypoint. Speed 162 m/s (~315 KTAS ~ 250 KIAS
#      at FL150) on WP1, WP2, the orbit task and the unit; unit heading 225 deg.
#   2. Player_01: COMM1 preset 8 = 252.3 AM (ARCO 31, recovery tanker TANKER-3).
#
#   python tools/patch_aar_me.py --src [--dry-run]          # src/mission (Template, then build.py)
#   python tools/patch_aar_me.py "<path>.miz" [--dry-run]   # a .miz IN PLACE (CAS (L)),
#                                                            # backup -> <dir>/BackUps/<name>_before-aar-me-<stamp>.miz
# The .miz path rewrites only the 'mission' entry (key-sorted, as extract.py writes it);
# every other archive entry is copied unchanged.

import copy
import datetime
import math
import os
import shutil
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, ".."))
sys.path.insert(0, REPO)
import dcslua  # noqa: E402

TANKER_GROUP = b"TANKER-1"
HERO_UNIT = b"Player_01"
SPEED_MS = 162.0
INBOUND_DEG = 225.0
LEG_NM = 25.0
NM_M = 1852.0
PRESET_RADIO, PRESET_CH, PRESET_MHZ = 1, 8, 252.3


def find_dicts(node, pred, out):
    if isinstance(node, dict):
        if pred(node):
            out.append(node)
        for v in node.values():
            find_dicts(v, pred, out)
    return out


def one(found, what):
    if len(found) != 1:
        sys.exit("expected exactly one %s, found %d" % (what, len(found)))
    return found[0]


def r(v):
    return round(v, 6)


def patch(m):
    """Applies the changes to the mission table. Returns a list of change descriptions."""
    changes = []

    # ---- 1. TANKER-1 race-track
    g = one(find_dicts(m, lambda d: d.get(b"name") == TANKER_GROUP and b"route" in d and b"units" in d, []),
            "group TANKER-1")
    pts = g[b"route"][b"points"]
    wp1 = pts[1]
    tasks = wp1[b"task"][b"params"][b"tasks"]
    orbit = one([t for t in tasks.values() if t.get(b"id") == b"Orbit"], "Orbit task on TANKER-1 WP1")
    op = orbit[b"params"]
    if op.get(b"pattern") != b"Race-Track":
        changes.append("TANKER-1 orbit pattern %s -> Race-Track" % op.get(b"pattern", b"?").decode())
        op[b"pattern"] = b"Race-Track"
    if op.get(b"speed") != SPEED_MS:
        changes.append("TANKER-1 orbit speed %s -> %s m/s" % (op.get(b"speed"), SPEED_MS))
        op[b"speed"] = SPEED_MS
        op[b"speedEdited"] = True

    a = math.radians(INBOUND_DEG)
    x2 = r(wp1[b"x"] + LEG_NM * NM_M * math.cos(a))   # x = north
    y2 = r(wp1[b"y"] + LEG_NM * NM_M * math.sin(a))   # y = east
    if 2 not in pts:
        wp2 = copy.deepcopy(wp1)
        wp2[b"task"] = {b"id": b"ComboTask", b"params": {b"tasks": {}}}
        wp2[b"ETA_locked"] = False
        pts[2] = wp2
        changes.append("TANKER-1 WP2 added (Race-Track end, %.0f deg / %.0f NM)" % (INBOUND_DEG, LEG_NM))
    wp2 = pts[2]
    if (wp2[b"x"], wp2[b"y"]) != (x2, y2):
        if not any("WP2 added" in c for c in changes):
            changes.append("TANKER-1 WP2 moved to %.0f deg / %.0f NM" % (INBOUND_DEG, LEG_NM))
        wp2[b"x"], wp2[b"y"] = x2, y2
    wp2[b"alt"] = wp1[b"alt"]
    wp2[b"alt_type"] = wp1[b"alt_type"]
    wp2[b"ETA"] = r(LEG_NM * NM_M / SPEED_MS)
    for name, wp in ((b"WP1", wp1), (b"WP2", wp2)):
        if wp.get(b"speed") != SPEED_MS:
            changes.append("TANKER-1 %s speed %s -> %s m/s" % (name.decode(), wp.get(b"speed"), SPEED_MS))
            wp[b"speed"] = SPEED_MS

    hdg = r(math.radians(INBOUND_DEG))
    for u in g[b"units"].values():
        if u.get(b"speed") != SPEED_MS:
            changes.append("TANKER-1 unit %s speed %s -> %s m/s" % (u[b"name"].decode(), u.get(b"speed"), SPEED_MS))
            u[b"speed"] = SPEED_MS
        if u.get(b"heading") != hdg:
            changes.append("TANKER-1 unit %s heading -> %.0f deg" % (u[b"name"].decode(), INBOUND_DEG))
            u[b"heading"] = hdg
            u[b"psi"] = -hdg

    # ---- 2. Player_01 COMM1 preset 8
    u = one(find_dicts(m, lambda d: d.get(b"name") == HERO_UNIT and b"Radio" in d, []), "unit Player_01 with Radio")
    ch = u[b"Radio"][PRESET_RADIO][b"channels"]
    if ch.get(PRESET_CH) != PRESET_MHZ:
        changes.append("Player_01 COMM%d preset %d %s -> %s" % (PRESET_RADIO, PRESET_CH, ch.get(PRESET_CH), PRESET_MHZ))
        ch[PRESET_CH] = PRESET_MHZ
    mods = u[b"Radio"][PRESET_RADIO].get(b"modulations")
    if isinstance(mods, dict) and mods.get(PRESET_CH, 0) != 0:
        changes.append("Player_01 COMM%d preset %d modulation -> AM" % (PRESET_RADIO, PRESET_CH))
        mods[PRESET_CH] = 0
    return changes


def run_src(dry):
    path = os.path.join(REPO, "src", "mission")
    with open(path, "rb") as f:
        name, m = dcslua.parse(f.read())
    changes = patch(m)
    for c in changes:
        print("  " + c)
    if not changes:
        print("src/mission: no change")
        return
    if dry:
        print("dry run: src/mission not written")
        return
    with open(path, "wb") as f:
        f.write(dcslua.dump(name, m))
    print("written: src/mission (%d change(s)); next: python build.py" % len(changes))


def run_miz(miz, dry):
    with zipfile.ZipFile(miz) as z:
        name, m = dcslua.parse(z.read("mission"))
        changes = patch(m)
        for c in changes:
            print("  " + c)
        if not changes:
            print("%s: no change" % os.path.basename(miz))
            return
        if dry:
            print("dry run: .miz not written")
            return
        new_mission = dcslua.dump(name, m)
        bdir = os.path.join(os.path.dirname(os.path.abspath(miz)), "BackUps")
        os.makedirs(bdir, exist_ok=True)
        stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
        backup = os.path.join(bdir, "%s_before-aar-me-%s.miz" % (os.path.splitext(os.path.basename(miz))[0], stamp))
        shutil.copy2(miz, backup)
        print("backup", backup)
        tmp = miz + ".tmp"
        with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as out:
            for info in z.infolist():
                out.writestr(info, new_mission if info.filename == "mission" else z.read(info.filename))
    with zipfile.ZipFile(tmp) as t:
        bad = t.testzip()
        if bad:
            os.remove(tmp)
            sys.exit("zip test failed on %s, original untouched" % bad)
    os.replace(tmp, miz)
    print("written: %s (%d change(s))" % (miz, len(changes)))


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if a != "--dry-run"]
    dry = "--dry-run" in sys.argv[1:]
    if args == ["--src"]:
        run_src(dry)
    elif len(args) == 1 and args[0].lower().endswith(".miz"):
        run_miz(args[0], dry)
    else:
        sys.exit(__doc__ or "usage: patch_aar_me.py --src | <file.miz> [--dry-run]")
