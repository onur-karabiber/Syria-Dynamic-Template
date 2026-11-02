# sync_missions.py | v1.0.0
# Keeps the three parallel missions in step (decision Onur 2026-11-02):
#   Syria_Dynamic_Template.miz        <- built from src/ + scripts/ (build.py)
#   Syria_Dynamic_Template HOUND.miz  <- GENERATED: template + Hound ELINT (tools/add_elint.py)
#   Close Air Support (L).miz         <- own mission (lighter, no RAT / ambient radios); scripts, sounds and
#                                        kneeboard pages refreshed from the repo (tools/refresh_scripts.py)
#
#   python tools/sync_missions.py            # all three
#   python tools/sync_missions.py --dry-run  # report only (build to build/ only, refresh dry run)
#   options: --force-template (build.py --force), --force-hound, --skip-cas, --skip-hound
#
# Steps
#   1. HOUND guard: the existing HOUND .miz must equal add_elint(the template currently deployed) in its
#      ME data (mission, dictionary, mapResource, options, warehouses). If not, it was edited in the ME
#      (e.g. ELINT towers moved) and regenerating it would lose that -> stop (--force-hound overrides).
#      Tower positions belong in tools/add_elint.py TOWERS, not in the HOUND .miz.
#   2. python build.py  (its copy guard refuses when the deployed template has unextracted ME edits)
#   3. HOUND: old file -> BackUps/<name>_before-sync-<UTC time>.miz, then add_elint(template, HOUND)
#   4. CAS (L): refresh_scripts.py --sounds <every src/Sounds set the CAS .miz also has>
#      --kneeboard src/KNEEBOARD/IMAGES (backup by refresh_scripts itself)
# Not covered: ScoreCards/ and PlaneCaptain/ pictures in CAS (L) (tools/score_cards/install_score_display.py),
# ME-level changes (units, triggers) in CAS (L): those stay manual / per-tool (add_script.py --miz, ...).

import datetime
import os
import shutil
import subprocess
import sys
import tempfile
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, ".."))
sys.path.insert(0, REPO)
import config  # noqa: E402

TEMPLATE = config.deployed_miz()
HOUND = os.path.join(config.MISSIONS_DIR, "Syria_Dynamic_Template HOUND.miz")
CAS = os.path.join(config.MISSIONS_DIR, "Close Air Support (L).miz")
ME_DATA = ["mission", "l10n/DEFAULT/dictionary", "l10n/DEFAULT/mapResource", "options", "warehouses"]
PY = sys.executable or "python"


def run(args):
    print(">> " + " ".join(('"%s"' % a) if " " in a else a for a in args))
    return subprocess.call(args, cwd=REPO)


def me_data(path):
    with zipfile.ZipFile(path) as z:
        names = set(z.namelist())
        return {n: (z.read(n) if n in names else None) for n in ME_DATA}


def hound_guard():
    """True if HOUND is missing or equals add_elint(deployed template)."""
    if not os.path.isfile(HOUND):
        return True
    if not os.path.isfile(TEMPLATE):
        print("no deployed template to compare HOUND with")
        return False
    with tempfile.TemporaryDirectory() as td:
        ref = os.path.join(td, "ref.miz")
        with open(os.devnull, "w") as dn:
            rc = subprocess.call([PY, os.path.join(HERE, "add_elint.py"), TEMPLATE, ref], cwd=REPO, stdout=dn)
        if rc != 0 or not os.path.isfile(ref):
            print("HOUND guard: add_elint on the deployed template failed (rc %s)" % rc)
            return False
        a, b = me_data(HOUND), me_data(ref)
    bad = [n for n in ME_DATA if a[n] != b[n]]
    if bad:
        print("HOUND guard: %s differs from template + Hound in %s (ME edits in HOUND?)" % (HOUND, ", ".join(bad)))
        return False
    return True


def sound_sets():
    src = os.path.join(REPO, "src", "Sounds")
    have = sorted(d for d in os.listdir(src) if os.path.isdir(os.path.join(src, d)))
    with zipfile.ZipFile(CAS) as z:
        cas = {n.split("/")[1] for n in z.namelist() if n.startswith("Sounds/") and n.count("/") >= 2}
    return [d for d in have if d in cas]


def main():
    argv = sys.argv[1:]
    dry = "--dry-run" in argv
    ts = datetime.datetime.utcnow().strftime("%Y%m%d-%H%M%S")

    do_hound = "--skip-hound" not in argv
    if do_hound and "--force-hound" not in argv and not hound_guard():
        print("STOP: HOUND not regenerated. Move ME edits into tools/add_elint.py, or --force-hound / --skip-hound.")
        return 2

    rc = run([PY, "build.py"] + (["--no-deploy"] if dry else []) + (["--force"] if "--force-template" in argv else []))
    if rc != 0:
        print("STOP: build.py returned %d" % rc)
        return rc

    if do_hound and not dry:
        if os.path.isfile(HOUND):
            bdir = os.path.join(config.MISSIONS_DIR, "BackUps")
            os.makedirs(bdir, exist_ok=True)
            bak = os.path.join(bdir, "Syria_Dynamic_Template HOUND_before-sync-%s.miz" % ts)
            shutil.move(HOUND, bak)
            print("backup " + bak)
        rc = run([PY, os.path.join("tools", "add_elint.py"), TEMPLATE, HOUND])
        if rc != 0:
            print("STOP: add_elint.py returned %d" % rc)
            return rc
    elif do_hound:
        print("dry run: HOUND would be regenerated from %s" % TEMPLATE)

    if "--skip-cas" not in argv:
        if not os.path.isfile(CAS):
            print("no CAS (L) .miz: %s" % CAS)
        else:
            args = [PY, os.path.join("tools", "refresh_scripts.py"), CAS]
            for s in sound_sets():
                args += ["--sounds", s]
            args += ["--kneeboard", os.path.join("src", "KNEEBOARD", "IMAGES")]
            if dry:
                args.append("--dry-run")
            rc = run(args)
            if rc != 0:
                print("STOP: refresh_scripts.py returned %d" % rc)
                return rc
    print("sync done" + (" (dry run)" if dry else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
