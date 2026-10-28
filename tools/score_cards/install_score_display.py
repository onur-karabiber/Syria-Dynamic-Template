# install_score_display.py | v1.2.1
# Installs / updates Score_Display in a .miz IN PLACE, after a backup.
#
#   python tools/score_cards/install_score_display.py "<path>/Close Air Support (L).miz"
#
#   1. backup  -> <dir>/BackUps/<name>_before-SD-<version>.miz; v1.2.1: if that exists
#                 (asset-only update, same script version) -> ..._before-SD-<version>-2.miz, -3 ...
#   2. assets  -> ScoreCards/*.png, PlaneCaptain/*.png (v1.1.0), Sounds/SCORE/*.ogg
#                 from out/; old copies of these folders are replaced
#   3. script  -> l10n/DEFAULT/Score_Display.lua from scripts/ (source of truth);
#                 first install also adds a mapResource key and one
#                 a_do_script_file action at the end of the mission-start
#                 trigger that loads Core_Scoring.lua (so after Deck_Park too)
#   4. v1.1.0: every other .lua named in mapResource is refreshed from scripts/
#                 too (same rule as build.py: scripts/ is the source of truth);
#                 the ones whose content changed are listed
#   5. v1.2.0: refuses when Score_Display CFG.PC.IDS and out/PlaneCaptain/*.png differ
#                 (a listed id without a file would show nothing and suppress the text)
# Re-running with a newer scripts/Score_Display.lua refreshes script + assets.
# ScoreCards/ and Sounds/SCORE/ survive Mission Editor saves (tested 2026-10-27).

import io
import os
import re
import shutil
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, REPO)
import dcslua  # noqa: E402

SCRIPT = "Score_Display.lua"
ASSET_DIRS = (("ScoreCards", os.path.join(HERE, "out", "ScoreCards")),
              ("PlaneCaptain", os.path.join(HERE, "out", "PlaneCaptain")),
              ("Sounds/SCORE", os.path.join(HERE, "out", "Sounds", "SCORE")))
ASSET_PREFIXES = tuple(a + "/" for a, _ in ASSET_DIRS)


def script_version(path):
    first = open(path, encoding="utf-8").readline()
    m = re.match(r"--\s*Score_Display\s*\|\s*v([\d.]+)", first)
    if not m:
        sys.exit("bad header line in " + path)
    return m.group(1)


def main(src):
    if not os.path.isfile(src):
        sys.exit("not found: " + src)
    lua_path = os.path.join(REPO, "scripts", SCRIPT)
    ver = script_version(lua_path)
    src_lua = open(lua_path, encoding="utf-8").read()
    m = re.search(r"IDS\s*=\s*\{([^}]*)\}", src_lua)
    ids = set(re.findall(r'"([^"]+)"', m.group(1))) if m else set()
    pc_dir = os.path.join(HERE, "out", "PlaneCaptain")
    files = {f[:-4] for f in os.listdir(pc_dir) if f.endswith(".png") and f != "blank.png"}
    if ids != files:
        sys.exit("CFG.PC.IDS / out/PlaneCaptain mismatch - only in IDS: %s, only files: %s"
                 % (sorted(ids - files), sorted(files - ids)))

    add = {"l10n/DEFAULT/" + SCRIPT: lua_path}
    for arc, d in ASSET_DIRS:
        for f in sorted(os.listdir(d)):
            add[arc + "/" + f] = os.path.join(d, f)

    zin = zipfile.ZipFile(src)
    names = zin.namelist()
    _, mission = dcslua.parse(zin.read("mission"))
    _, mapres = dcslua.parse(zin.read("l10n/DEFAULT/mapResource"))

    key = next((k for k, v in mapres.items() if v == SCRIPT.encode()), None)
    if key is None:
        core = next((k for k, v in mapres.items() if v == b"Core_Scoring.lua"), None)
        if core is None:
            sys.exit("Core_Scoring.lua not in mapResource")
        rules = mission[b"trigrules"]
        rk = next((k for k, r in rules.items()
                   if any(a.get(b"file") == core for a in r.get(b"actions", {}).values())), None)
        if rk is None:
            sys.exit("no trigger loads Core_Scoring.lua")
        nums = [int(m.group(1)) for k in mapres
                for m in [re.match(rb"ResKey_Action_(\d+)$", k)] if m]
        n = max(nums + [int(mission[b"maxDictId"])]) + 1
        key = b"ResKey_Action_%d" % n
        mission[b"maxDictId"] = n
        acts = rules[rk][b"actions"]
        acts[max(acts) + 1] = {b"predicate": b"a_do_script_file", b"file": key}
        ta = mission[b"trig"][b"actions"]
        ta[rk] = ta[rk] + b'a_do_script_file(getValueResourceByKey("%s"));' % key
        mapres[key] = SCRIPT.encode()
        new_mission = dcslua.dump("mission", mission)
        new_mapres = dcslua.dump("mapResource", mapres)
        print("first install: trigger %d '%s' +%s" % (rk, rules[rk].get(b"comment", b"").decode(), key.decode()))
    else:
        new_mission = new_mapres = None
        print("update: %s already mapped to %s" % (SCRIPT, key.decode()))

    for v in sorted(set(mapres.values())):
        nm = v.decode()
        sp = os.path.join(REPO, "scripts", nm)
        if nm.lower().endswith(".lua") and nm != SCRIPT and os.path.isfile(sp):
            arc = "l10n/DEFAULT/" + nm
            old = zin.read(arc) if arc in names else None
            if old != open(sp, "rb").read():
                print("refresh (changed):", nm, "->", open(sp, encoding="utf-8").readline().strip())
            add[arc] = sp

    bdir = os.path.join(os.path.dirname(src), "BackUps")
    os.makedirs(bdir, exist_ok=True)
    stem = "%s_before-SD-%s" % (os.path.splitext(os.path.basename(src))[0], ver)
    backup, k = os.path.join(bdir, stem + ".miz"), 2
    while os.path.exists(backup):
        backup, k = os.path.join(bdir, "%s-%d.miz" % (stem, k)), k + 1
    shutil.copy2(src, backup)
    print("backup", backup)

    buf = io.BytesIO()   # build in memory, then overwrite src (no rename/delete needed)
    drop = lambda nm: (nm.startswith(ASSET_PREFIXES) or nm in add
                       or (new_mission is not None and nm in ("mission", "l10n/DEFAULT/mapResource")))
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zout:
        for nm in names:
            if not drop(nm):
                zout.writestr(zin.getinfo(nm), zin.read(nm))
        if new_mission is not None:
            zout.writestr("mission", new_mission)
            zout.writestr("l10n/DEFAULT/mapResource", new_mapres)
        for arc, p in add.items():
            ct = zipfile.ZIP_STORED if p.lower().endswith((".png", ".ogg")) else zipfile.ZIP_DEFLATED
            zout.write(p, arc, compress_type=ct)
    zin.close()
    with open(src, "wb") as f:
        f.write(buf.getvalue())
    print("Score_Display v%s installed: %d files -> %s (%d bytes)" % (ver, len(add), src, os.path.getsize(src)))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: install_score_display.py <mission.miz>")
    main(sys.argv[1])
