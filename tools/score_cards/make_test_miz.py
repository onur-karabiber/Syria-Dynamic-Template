# make_test_miz.py | v0.1.0
# Builds a throwaway test copy of a mission with the score-card assets and
# Score_Display_Test.lua. The source .miz is only read, never written.
#
#   python tools/score_cards/make_test_miz.py "<path>/Close Air Support (L).miz"
#   -> "<path>/Close Air Support (L)_ScoreCardTest.miz"
#
# Packs:
#   ScoreCards/*.png              (out/ScoreCards + out/test/sc_test_root.png)
#   Sounds/SCORE/*.ogg            (out/Sounds/SCORE)
#   l10n/DEFAULT/sc_test_l10n.png (path probes P2..P4), mapResource ResKey_SCT_Pic
#   l10n/DEFAULT/Score_Display_Test.lua + one a_do_script_file action appended
#   to the mission-start trigger that loads Core_Scoring.lua (runs after it).

import os
import re
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, REPO)
import dcslua  # noqa: E402

SCRIPT = "Score_Display_Test.lua"
PIC_KEY = b"ResKey_SCT_Pic"
PIC_FILE = b"sc_test_l10n.png"


def main(src):
    if not os.path.isfile(src):
        sys.exit("not found: " + src)
    dst = os.path.splitext(src)[0] + "_ScoreCardTest.miz"
    zin = zipfile.ZipFile(src)
    names = zin.namelist()

    _, mission = dcslua.parse(zin.read("mission"))
    _, mapres = dcslua.parse(zin.read("l10n/DEFAULT/mapResource"))

    core_key = next((k for k, v in mapres.items() if v == b"Core_Scoring.lua"), None)
    if core_key is None:
        sys.exit("Core_Scoring.lua not in mapResource")
    if any(v == SCRIPT.encode() for v in mapres.values()):
        sys.exit(SCRIPT + " already referenced - use a clean source .miz")

    nums = [int(m.group(1)) for k in mapres
            for m in [re.match(rb"ResKey_Action_(\d+)$", k)] if m]
    n = max(nums + [int(mission[b"maxDictId"])]) + 1
    script_key = b"ResKey_Action_%d" % n
    mission[b"maxDictId"] = n

    rules = mission[b"trigrules"]
    rk = next((k for k, r in rules.items()
               if any(a.get(b"file") == core_key for a in r.get(b"actions", {}).values())), None)
    if rk is None:
        sys.exit("no trigger loads Core_Scoring.lua")
    acts = rules[rk][b"actions"]
    acts[max(acts) + 1] = {b"predicate": b"a_do_script_file", b"file": script_key}
    trig_actions = mission[b"trig"][b"actions"]
    trig_actions[rk] = trig_actions[rk] + b'a_do_script_file(getValueResourceByKey("%s"));' % script_key

    mapres[script_key] = SCRIPT.encode()
    mapres[PIC_KEY] = PIC_FILE

    add = {
        "l10n/DEFAULT/" + SCRIPT: os.path.join(REPO, "scripts", SCRIPT),
        "l10n/DEFAULT/" + PIC_FILE.decode(): os.path.join(HERE, "out", "test", PIC_FILE.decode()),
        "ScoreCards/sc_test_root.png": os.path.join(HERE, "out", "test", "sc_test_root.png"),
    }
    for sub, arc in (("ScoreCards", "ScoreCards"), (os.path.join("Sounds", "SCORE"), "Sounds/SCORE")):
        d = os.path.join(HERE, "out", sub)
        for f in sorted(os.listdir(d)):
            add[arc + "/" + f] = os.path.join(d, f)
    for p in add.values():
        if not os.path.isfile(p):
            sys.exit("missing asset (run make_cards.py / make_sfx.py first): " + p)

    with zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED) as zout:
        for nm in names:
            if nm in ("mission", "l10n/DEFAULT/mapResource") or nm in add:
                continue
            zout.writestr(zin.getinfo(nm), zin.read(nm))
        zout.writestr("mission", dcslua.dump("mission", mission))
        zout.writestr("l10n/DEFAULT/mapResource", dcslua.dump("mapResource", mapres))
        for arc, p in add.items():
            # PNG/OGG are already compressed
            ct = zipfile.ZIP_STORED if p.lower().endswith((".png", ".ogg")) else zipfile.ZIP_DEFLATED
            zout.write(p, arc, compress_type=ct)

    print("trigger %d '%s': +%s -> %s" % (rk, rules[rk].get(b"comment", b"").decode(), script_key.decode(), SCRIPT))
    print("added %d files" % len(add))
    print("wrote", dst, os.path.getsize(dst), "bytes")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__ or "usage: make_test_miz.py <mission.miz>")
    main(sys.argv[1])
