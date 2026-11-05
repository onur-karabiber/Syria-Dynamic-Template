# add_script.py | v1.1.1
# v1.1.1: usage example uses the 2026-11-05 mission name (SEA2STEEL.miz).
# v1.1.0 (2026-11-04): --after <script.lua> inserts the action right after that script's action, in that script's
#         trigger (e.g. CAS_Pack.lua after mist_4_5_126.lua in the MOOSE trigger); without it: end of the trigger
#         that loads Core_Scoring.lua, as before.
# Adds one "Do Script File" action for scripts/<name>.lua to the mission-start trigger
# that loads Core_Scoring.lua (appended at its end), in either
#   * the unpacked template:  python tools/add_script.py --src Missile_Defense.lua
#       -> edits src/mission + src/l10n/DEFAULT/mapResource (then: python build.py)
#   * a .miz in place:        python tools/add_script.py --miz "<...>/SEA2STEEL.miz" Missile_Defense.lua
#       -> backup BackUps/<name>_before-add-<script>-<YYYYmmdd-HHMMSS>.miz, then the
#          action, the mapResource key and l10n/DEFAULT/<script> from scripts/
# Refuses when the script is already referenced (updates: build.py / refresh_scripts.py).
# The new key is ResKey_Action_<max+1>; maxDictId follows it.

import argparse
import io
import os
import re
import shutil
import sys
import time
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, ".."))
sys.path.insert(0, REPO)
import dcslua  # noqa: E402

ANCHOR = b"Core_Scoring.lua"


def add(mission, mapres, script, after=None):
    sb = script.encode()
    if any(v == sb for v in mapres.values()):
        sys.exit(script + " is already referenced in mapResource")
    anchor_name = after.encode() if after else ANCHOR
    anchor = next((k for k, v in mapres.items() if v == anchor_name), None)
    if anchor is None:
        sys.exit(anchor_name.decode() + " not in mapResource")
    rules = mission[b"trigrules"]
    rk = next((k for k, r in rules.items()
               if any(a.get(b"file") == anchor for a in r.get(b"actions", {}).values())), None)
    if rk is None:
        sys.exit("no trigger loads " + anchor_name.decode())
    nums = [int(m.group(1)) for k in mapres for m in [re.match(rb"ResKey_Action_(\d+)$", k)] if m]
    n = max(nums + [int(mission[b"maxDictId"])]) + 1
    key = b"ResKey_Action_%d" % n
    mission[b"maxDictId"] = n
    acts = rules[rk][b"actions"]
    new_act = {b"predicate": b"a_do_script_file", b"file": key}
    ta = mission[b"trig"][b"actions"]
    call = b'a_do_script_file(getValueResourceByKey("%s"));' % key
    if after:
        pos = next(i for i in sorted(acts) if acts[i].get(b"file") == anchor)
        items = [acts[i] for i in sorted(acts)]
        items.insert(pos, new_act)          # sorted keys start at 1 -> list index pos is right after the anchor
        rules[rk][b"actions"] = {i + 1: a for i, a in enumerate(items)}
        ref = b'a_do_script_file(getValueResourceByKey("%s"));' % anchor
        if ta[rk].count(ref) != 1:
            sys.exit("compiled trig.actions[%d] does not contain the anchor call exactly once" % rk)
        ta[rk] = ta[rk].replace(ref, ref + call)
    else:
        acts[max(acts) + 1] = new_act
        ta[rk] = ta[rk] + call
    mapres[key] = sb
    print("trigger %d '%s': +%s -> %s" % (rk, rules[rk].get(b"comment", b"").decode(), key.decode(), script))


def do_src(script, after=None):
    mp = os.path.join(REPO, "src", "mission")
    rp = os.path.join(REPO, "src", "l10n", "DEFAULT", "mapResource")
    _, mission = dcslua.parse(open(mp, "rb").read())
    _, mapres = dcslua.parse(open(rp, "rb").read())
    add(mission, mapres, script, after)
    open(mp, "wb").write(dcslua.dump("mission", mission))
    open(rp, "wb").write(dcslua.dump("mapResource", mapres))
    print("src/ updated - run: python build.py")


def do_miz(miz, script, after=None):
    sp = os.path.join(REPO, "scripts", script)
    zin = zipfile.ZipFile(miz)
    names = zin.namelist()
    _, mission = dcslua.parse(zin.read("mission"))
    _, mapres = dcslua.parse(zin.read("l10n/DEFAULT/mapResource"))
    add(mission, mapres, script, after)
    bdir = os.path.join(os.path.dirname(miz), "BackUps")
    os.makedirs(bdir, exist_ok=True)
    backup = os.path.join(bdir, "%s_before-add-%s-%s.miz" % (
        os.path.splitext(os.path.basename(miz))[0], os.path.splitext(script)[0], time.strftime("%Y%m%d-%H%M%S")))
    shutil.copy2(miz, backup)
    print("backup", backup)
    arc = "l10n/DEFAULT/" + script
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zout:
        for nm in names:
            if nm in ("mission", "l10n/DEFAULT/mapResource", arc):
                continue
            zout.writestr(zin.getinfo(nm), zin.read(nm))
        zout.writestr("mission", dcslua.dump("mission", mission))
        zout.writestr("l10n/DEFAULT/mapResource", dcslua.dump("mapResource", mapres))
        zout.write(sp, arc)
    zin.close()
    with open(miz, "wb") as f:
        f.write(buf.getvalue())
    print("written", miz, os.path.getsize(miz), "bytes")


def main():
    ap = argparse.ArgumentParser(description="add a Do Script File action for scripts/<script>")
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--src", action="store_true", help="edit the unpacked template in src/")
    g.add_argument("--miz", help="edit this .miz in place (after a backup)")
    ap.add_argument("script", help="file name in scripts/, e.g. Missile_Defense.lua")
    ap.add_argument("--after", help="insert right after this script's Do Script File action (v1.1.0)")
    a = ap.parse_args()
    sp = os.path.join(REPO, "scripts", a.script)
    if not os.path.isfile(sp):
        sys.exit("not in scripts/: " + a.script)
    first = open(sp, encoding="utf-8").readline()
    if not re.match(r"--\s*\S+\s*\|\s*v[\d.]+", first):
        sys.exit("missing '-- Name | vX.Y.Z' header line: " + a.script)
    if a.src:
        do_src(a.script, a.after)
    else:
        do_miz(a.miz, a.script, a.after)


if __name__ == "__main__":
    main()
