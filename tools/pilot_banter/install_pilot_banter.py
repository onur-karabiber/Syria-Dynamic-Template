# install_pilot_banter.py | v1.0.0
# Installs / updates Pilot_Banter in a .miz IN PLACE, after a backup (CAS (L) only).
#
#   python tools/pilot_banter/install_pilot_banter.py "<path>/Close Air Support (L).miz"
#
#   0. checks   -> every AUDIO key in scripts/Pilot_Banter.lua has an .ogg in
#                  out/Sounds/PB/ and every .ogg there has an AUDIO key
#                  (run `python tts/make_clips.py --set pb` first)
#   1. backup   -> <dir>/BackUps/<name>_before-PB-<version>.miz (refuses if it exists)
#   2. assets   -> Sounds/PB/*.ogg from out/Sounds/PB/; the old Sounds/PB/ is replaced
#   3. script   -> l10n/DEFAULT/Pilot_Banter.lua from scripts/ (source of truth);
#                  first install also adds a mapResource key and one a_do_script_file
#                  action at the end of the mission-start trigger that loads
#                  Flight_Timeline.lua (else Score_Display.lua, else Core_Scoring.lua).
#                  Pilot_Banter reads every other module lazily, so the position only
#                  has to be after Menu_Manager (it retries the menu anyway).
#   4. every other .lua named in mapResource is refreshed from scripts/ too
#                  (same rule as build.py / install_score_display.py); changed ones listed
# Same mechanics as tools/score_cards/install_score_display.py v1.1.0.

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

SCRIPT = "Pilot_Banter.lua"
ASSET_DIRS = (("Sounds/PB", os.path.join(HERE, "out", "Sounds", "PB")),)
ASSET_PREFIXES = tuple(a + "/" for a, _ in ASSET_DIRS)
ANCHORS = (b"Flight_Timeline.lua", b"Score_Display.lua", b"Core_Scoring.lua")


def script_version(path):
    first = open(path, encoding="utf-8").readline()
    m = re.match(r"--\s*Pilot_Banter\s*\|\s*v([\d.]+)", first)
    if not m:
        sys.exit("bad header line in " + path)
    return m.group(1)


def audio_keys(path):
    src = open(path, encoding="utf-8").read()
    m = re.search(r"-- BEGIN AUDIO.*?\n(.*?)-- END AUDIO", src, re.S)
    if not m:
        sys.exit("AUDIO markers not found in " + path)
    return set(re.findall(r"^\s*([A-Za-z0-9_]+)\s*=\s*\{\s*len\s*=", m.group(1), re.M))


def main(src):
    if not os.path.isfile(src):
        sys.exit("not found: " + src)
    lua_path = os.path.join(REPO, "scripts", SCRIPT)
    ver = script_version(lua_path)

    keys = audio_keys(lua_path)
    snd = ASSET_DIRS[0][1]
    oggs = {os.path.splitext(f)[0] for f in os.listdir(snd)} if os.path.isdir(snd) else set()
    if not keys:
        sys.exit("AUDIO block is empty: run  python tts/make_clips.py --set pb")
    if keys - oggs or oggs - keys:
        sys.exit("AUDIO / clips mismatch. no .ogg: %s | no AUDIO key: %s"
                 % (sorted(keys - oggs), sorted(oggs - keys)))

    add = {"l10n/DEFAULT/" + SCRIPT: lua_path}
    for arc, d in ASSET_DIRS:
        for f in sorted(os.listdir(d)):
            if f.lower().endswith(".ogg"):
                add[arc + "/" + f] = os.path.join(d, f)

    zin = zipfile.ZipFile(src)
    names = zin.namelist()
    _, mission = dcslua.parse(zin.read("mission"))
    _, mapres = dcslua.parse(zin.read("l10n/DEFAULT/mapResource"))

    key = next((k for k, v in mapres.items() if v == SCRIPT.encode()), None)
    if key is None:
        rules = mission[b"trigrules"]
        rk = None
        for anchor in ANCHORS:
            ak = next((k for k, v in mapres.items() if v == anchor), None)
            if ak is None:
                continue
            rk = next((k for k, r in rules.items()
                       if any(a.get(b"file") == ak for a in r.get(b"actions", {}).values())), None)
            if rk is not None:
                print("anchor:", anchor.decode())
                break
        if rk is None:
            sys.exit("no trigger loads any of " + ", ".join(a.decode() for a in ANCHORS))
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
    backup = os.path.join(bdir, "%s_before-PB-%s.miz" % (os.path.splitext(os.path.basename(src))[0], ver))
    if os.path.exists(backup):
        sys.exit("backup exists, not overwriting: " + backup)
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
    print("Pilot_Banter v%s installed: %d clips, %d files -> %s (%d bytes)"
          % (ver, len(keys), len(add), src, os.path.getsize(src)))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: install_pilot_banter.py <mission.miz>")
    main(sys.argv[1])
