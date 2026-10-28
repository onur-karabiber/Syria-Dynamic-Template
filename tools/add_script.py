# add_script.py | v1.0.0
# Adds one "Do Script File" action for scripts/<name>.lua to the mission-start trigger
# that loads Core_Scoring.lua (appended at its end), in either
#   * the unpacked template:  python tools/add_script.py --src Missile_Defense.lua
#       -> edits src/mission + src/l10n/DEFAULT/mapResource (then: python build.py)
#   * a .miz in place:        python tools/add_script.py --miz "<...>/Close Air Support (L).miz" Missile_Defense.lua
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


def add(mission, mapres, script):
    sb = script.encode()
    if any(v == sb for v in mapres.values()):
        sys.exit(script + " is already referenced in mapResource")
    anchor = next((k for k, v in mapres.items() if v == ANCHOR), None)
    if anchor is None:
        sys.exit("Core_Scoring.lua not in mapResource")
    rules = mission[b"trigrules"]
    rk = next((k for k, r in rules.items()
               if any(a.get(b"file") == anchor for a in r.get(b"actions", {}).values())), None)
    if rk is None:
        sys.exit("no trigger loads Core_Scoring.lua")
    nums = [int(m.group(1)) for k in mapres for m in [re.match(rb"ResKey_Action_(\d+)$", k)] if m]
    n = max(nums + [int(mission[b"maxDictId"])]) + 1
    key = b"ResKey_Action_%d" % n
    mission[b"maxDictId"] = n
    acts = rules[rk][b"actions"]
    acts[max(acts) + 1] = {b"predicate": b"a_do_script_file", b"file": key}
    ta = mission[b"trig"][b"actions"]
    ta[rk] = ta[rk] + b'a_do_script_file(getValueResourceByKey("%s"));' % key
    mapres[key] = sb
    print("trigger %d '%s': +%s -> %s" % (rk, rules[rk].get(b"comment", b"").decode(), key.decode(), script))


def do_src(script):
    mp = os.path.join(REPO, "src", "mission")
    rp = os.path.join(REPO, "src", "l10n", "DEFAULT", "mapResource")
    _, mission = dcslua.parse(open(mp, "rb").read())
    _, mapres = dcslua.parse(open(rp, "rb").read())
    add(mission, mapres, script)
    open(mp, "wb").write(dcslua.dump("mission", mission))
    open(rp, "wb").write(dcslua.dump("mapResource", mapres))
    print("src/ updated - run: python build.py")


def do_miz(miz, script):
    sp = os.path.join(REPO, "scripts", script)
    zin = zipfile.ZipFile(miz)
    names = zin.namelist()
    _, mission = dcslua.parse(zin.read("mission"))
    _, mapres = dcslua.parse(zin.read("l10n/DEFAULT/mapResource"))
    add(mission, mapres, script)
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
    a = ap.parse_args()
    sp = os.path.join(REPO, "scripts", a.script)
    if not os.path.isfile(sp):
        sys.exit("not in scripts/: " + a.script)
    first = open(sp, encoding="utf-8").readline()
    if not re.match(r"--\s*\S+\s*\|\s*v[\d.]+", first):
        sys.exit("missing '-- Name | vX.Y.Z' header line: " + a.script)
    if a.src:
        do_src(a.script)
    else:
        do_miz(a.miz, a.script)


if __name__ == "__main__":
    main()
