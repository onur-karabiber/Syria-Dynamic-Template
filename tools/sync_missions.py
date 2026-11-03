# sync_missions.py | v1.2.0
# v1.2.0: fourth mission "Close Air Support (L) HOUND.miz" (decision Onur 2026-11-04: CAS (L), the template and
#         both HOUND variants always updated together). It is GENERATED: add_elint(CAS (L)) - checked 2026-11-04,
#         byte-identical to add_elint of the deployed CAS (L). Same guard as the template HOUND, against the CAS (L)
#         currently deployed (before the refresh); regenerated after the CAS (L) refresh. Options
#         --force-cas-hound, --skip-cas-hound (--skip-cas skips it too). A missing CAS HOUND is created.
# v1.1.0: CAS (L) also gets the picture folders src/FlightReport, src/ScoreCards, src/PlaneCaptain (--folder,
#         refresh_scripts.py >= v1.4.0); "Not covered" below no longer applies to them.
# Keeps the four parallel missions in step (decisions Onur 2026-11-02 / 2026-11-04):
#   Syria_Dynamic_Template.miz          <- built from src/ + scripts/ (build.py)
#   Syria_Dynamic_Template HOUND.miz    <- GENERATED: template + Hound ELINT (tools/add_elint.py)
#   Close Air Support (L).miz           <- own mission (lighter, no RAT / ambient radios); scripts, sounds and
#                                          kneeboard pages refreshed from the repo (tools/refresh_scripts.py)
#   Close Air Support (L) HOUND.miz     <- GENERATED: CAS (L) + Hound ELINT (tools/add_elint.py)
#
#   python tools/sync_missions.py            # all four
#   python tools/sync_missions.py --dry-run  # report only (build to build/ only, refresh dry run)
#   options: --force-template (build.py --force), --force-hound, --force-cas-hound, --skip-cas, --skip-hound,
#            --skip-cas-hound
#
# Steps
#   1. Guards: each HOUND .miz must equal add_elint(its base as currently deployed) in its ME data (mission,
#      dictionary, mapResource, options, warehouses). If not, it was edited in the ME (e.g. ELINT towers moved)
#      and regenerating it would lose that -> stop (--force-hound / --force-cas-hound override).
#      Tower positions belong in tools/add_elint.py TOWERS, not in a HOUND .miz.
#   2. python build.py  (its copy guard refuses when the deployed template has unextracted ME edits)
#   3. HOUND: old file -> BackUps/<name>_before-sync-<UTC time>.miz, then add_elint(template, HOUND)
#   4. CAS (L): refresh_scripts.py --sounds <every src/Sounds set the CAS .miz also has>
#      --kneeboard src/KNEEBOARD/IMAGES --folder <pictures> (backup by refresh_scripts itself)
#   5. CAS (L) HOUND: old file -> BackUps/<name>_before-sync-<UTC time>.miz, then add_elint(CAS (L), CAS HOUND)
# Not covered: ME-level changes (units, triggers) in CAS (L): those stay manual / per-tool (add_script.py --miz, ...);
# the TEST variants (tools/make_test_variant.py) are rebuilt separately from CAS (L).

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
CAS_HOUND = os.path.join(config.MISSIONS_DIR, "Close Air Support (L) HOUND.miz")   # v1.2.0
ME_DATA = ["mission", "l10n/DEFAULT/dictionary", "l10n/DEFAULT/mapResource", "options", "warehouses"]
PY = sys.executable or "python"
PICTURE_FOLDERS = ["FlightReport", "ScoreCards", "PlaneCaptain"]   # v1.1.0


def run(args):
    print(">> " + " ".join(('"%s"' % a) if " " in a else a for a in args))
    return subprocess.call(args, cwd=REPO)


def me_data(path):
    with zipfile.ZipFile(path) as z:
        names = set(z.namelist())
        return {n: (z.read(n) if n in names else None) for n in ME_DATA}


def hound_guard(hound=None, base=None):
    """True if the HOUND variant is missing or equals add_elint(its deployed base) in its ME data.
    v1.2.0: generic (template HOUND by default, CAS (L) HOUND with hound=CAS_HOUND, base=CAS)."""
    hound, base = hound or HOUND, base or TEMPLATE
    if not os.path.isfile(hound):
        return True
    if not os.path.isfile(base):
        print("no deployed %s to compare %s with" % (os.path.basename(base), os.path.basename(hound)))
        return False
    with tempfile.TemporaryDirectory() as td:
        ref = os.path.join(td, "ref.miz")
        with open(os.devnull, "w") as dn:
            rc = subprocess.call([PY, os.path.join(HERE, "add_elint.py"), base, ref], cwd=REPO, stdout=dn)
        if rc != 0 or not os.path.isfile(ref):
            print("HOUND guard: add_elint on %s failed (rc %s)" % (os.path.basename(base), rc))
            return False
        a, b = me_data(hound), me_data(ref)
    bad = [n for n in ME_DATA if a[n] != b[n]]
    if bad:
        print("HOUND guard: %s differs from %s + Hound in %s (ME edits in the HOUND file?)"
              % (os.path.basename(hound), os.path.basename(base), ", ".join(bad)))
        return False
    return True


def regen_hound(hound, base, ts):
    """v1.2.0: backup the old HOUND file, then add_elint(base, hound). Returns the exit code."""
    if os.path.isfile(hound):
        bdir = os.path.join(config.MISSIONS_DIR, "BackUps")
        os.makedirs(bdir, exist_ok=True)
        stem = os.path.splitext(os.path.basename(hound))[0]
        bak = os.path.join(bdir, "%s_before-sync-%s.miz" % (stem, ts))
        shutil.move(hound, bak)
        print("backup " + bak)
    return run([PY, os.path.join("tools", "add_elint.py"), base, hound])


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
    do_cas = "--skip-cas" not in argv
    do_cas_hound = do_cas and "--skip-cas-hound" not in argv   # v1.2.0
    # v1.2.0: both guards before anything is written (against the bases as currently deployed)
    if do_hound and "--force-hound" not in argv and not hound_guard():
        print("STOP: HOUND not regenerated. Move ME edits into tools/add_elint.py, or --force-hound / --skip-hound.")
        return 2
    if do_cas_hound and "--force-cas-hound" not in argv and os.path.isfile(CAS) and not hound_guard(CAS_HOUND, CAS):
        print("STOP: CAS (L) HOUND not regenerated. Move ME edits into CAS (L) or tools/add_elint.py, "
              "or --force-cas-hound / --skip-cas-hound.")
        return 2

    rc = run([PY, "build.py"] + (["--no-deploy"] if dry else []) + (["--force"] if "--force-template" in argv else []))
    if rc != 0:
        print("STOP: build.py returned %d" % rc)
        return rc

    if do_hound and not dry:
        rc = regen_hound(HOUND, TEMPLATE, ts)
        if rc != 0:
            print("STOP: add_elint.py returned %d" % rc)
            return rc
    elif do_hound:
        print("dry run: HOUND would be regenerated from %s" % TEMPLATE)

    if do_cas:
        if not os.path.isfile(CAS):
            print("no CAS (L) .miz: %s" % CAS)
        else:
            args = [PY, os.path.join("tools", "refresh_scripts.py"), CAS]
            for s in sound_sets():
                args += ["--sounds", s]
            args += ["--kneeboard", os.path.join("src", "KNEEBOARD", "IMAGES")]
            for fo in PICTURE_FOLDERS:                          # v1.1.0
                if os.path.isdir(os.path.join(REPO, "src", fo)):
                    args += ["--folder", fo]
            if dry:
                args.append("--dry-run")
            rc = run(args)
            if rc != 0:
                print("STOP: refresh_scripts.py returned %d" % rc)
                return rc
            if do_cas_hound and not dry:   # v1.2.0
                rc = regen_hound(CAS_HOUND, CAS, ts)
                if rc != 0:
                    print("STOP: add_elint.py (CAS HOUND) returned %d" % rc)
                    return rc
            elif do_cas_hound:
                print("dry run: CAS (L) HOUND would be regenerated from %s" % CAS)
    print("sync done" + (" (dry run)" if dry else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
