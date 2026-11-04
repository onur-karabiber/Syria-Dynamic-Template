# sync_missions.py | v1.4.0
# v1.4.0: CAS (L) is GENERATED from the template (tools/make_cas_l.py, decision Onur 2026-11-04 03:12). The cas
#         step backs up the old file and regenerates it (was: refresh_scripts.py on an own mission). Guard: the
#         deployed CAS (L) must equal make_cas_l(deployed template) in its ME data, else it was edited in the ME
#         and regenerating would lose that -> stop (--force-cas). The cas step now needs the guard token too.
# v1.3.1: cas-hound step expires the guard token (t = 0) when it cannot delete it (cloud device shell without
#         delete permission: PermissionError after a successful CAS HOUND regeneration, 2026-11-04).
# v1.3.0: --step guards|template|hound|cas|cas-hound runs one step (the device shell of a cloud session has a
#         180 s limit per call and kills background processes; the whole sync takes longer). Order: guards first
#         (writes build/sync_guard.json, valid 1 h; the HOUND steps refuse without it), then template, hound,
#         cas, cas-hound (removes the token). Without --step: all steps in one go, as before (Windows).
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
#   Close Air Support (L).miz           <- GENERATED (v1.4.0): template minus tools/cas_l_spec.json (no RAT /
#                                          ambient radios ...), tools/make_cas_l.py
#   Close Air Support (L) HOUND.miz     <- GENERATED: CAS (L) + Hound ELINT (tools/add_elint.py)
#
#   python tools/sync_missions.py            # all four
#   python tools/sync_missions.py --dry-run  # report only (build to build/ only, refresh dry run)
#   python tools/sync_missions.py --step guards   (then template, hound, cas, cas-hound: one call each)
#   options: --force-template (build.py --force), --force-hound, --force-cas (v1.4.0), --force-cas-hound, --skip-cas, --skip-hound,
#            --skip-cas-hound
#
# Steps
#   1. Guards: each HOUND .miz must equal add_elint(its base as currently deployed) in its ME data (mission,
#      dictionary, mapResource, options, warehouses). If not, it was edited in the ME (e.g. ELINT towers moved)
#      and regenerating it would lose that -> stop (--force-hound / --force-cas-hound override).
#      Tower positions belong in tools/add_elint.py TOWERS, not in a HOUND .miz.
#   2. python build.py  (its copy guard refuses when the deployed template has unextracted ME edits)
#   3. HOUND: old file -> BackUps/<name>_before-sync-<UTC time>.miz, then add_elint(template, HOUND)
#   4. CAS (L): old file -> BackUps/<name>_before-sync-<UTC time>.miz, then make_cas_l(template, CAS (L))
#   5. CAS (L) HOUND: old file -> BackUps/<name>_before-sync-<UTC time>.miz, then add_elint(CAS (L), CAS HOUND)
# ME edits go into the template only (src/, via the ME + extract.py); CAS (L) follows on the next sync. New template
# groups go into CAS (L) too and are reported (tools/make_cas_l.py: delete_groups or --accept-new).
# Not covered: the TEST variants (tools/make_test_variant.py) are rebuilt separately from CAS (L).

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


def backup(path, ts):
    bdir = os.path.join(config.MISSIONS_DIR, "BackUps")
    os.makedirs(bdir, exist_ok=True)
    bak = os.path.join(bdir, "%s_before-sync-%s.miz" % (os.path.splitext(os.path.basename(path))[0], ts))
    shutil.copy2(path, bak)
    print("backup " + bak)


def cas_guard():
    """v1.4.0: True if CAS (L) is missing or equals make_cas_l(deployed template) in its ME data."""
    if not os.path.isfile(CAS):
        return True
    return run([PY, os.path.join("tools", "make_cas_l.py"), "--check", TEMPLATE, CAS]) == 0


STEPS = ["guards", "template", "hound", "cas", "cas-hound"]   # v1.3.0
GUARD_TOKEN = os.path.join(REPO, "build", "sync_guard.json")
GUARD_MAX_S = 3600


def step_guards(argv, do_hound, do_cas_hound, do_cas=True):
    """Both guards before anything is written (against the bases as currently deployed)."""
    if do_hound and "--force-hound" not in argv and not hound_guard():
        print("STOP: HOUND not regenerated. Move ME edits into tools/add_elint.py, or --force-hound / --skip-hound.")
        return 2
    if do_cas and "--force-cas" not in argv and not cas_guard():   # v1.4.0
        print("STOP: CAS (L) differs from make_cas_l(template): it was edited in the ME. Make those edits in the "
              "template (src/), or --force-cas / --skip-cas.")
        return 2
    if do_cas_hound and "--force-cas-hound" not in argv and os.path.isfile(CAS) and not hound_guard(CAS_HOUND, CAS):
        print("STOP: CAS (L) HOUND not regenerated. Move ME edits into CAS (L) or tools/add_elint.py, "
              "or --force-cas-hound / --skip-cas-hound.")
        return 2
    return 0


def step_template(argv, dry):
    rc = run([PY, "build.py"] + (["--no-deploy"] if dry else []) + (["--force"] if "--force-template" in argv else []))
    if rc != 0:
        print("STOP: build.py returned %d" % rc)
    return rc


def step_hound(dry, ts):
    if dry:
        print("dry run: HOUND would be regenerated from %s" % TEMPLATE)
        return 0
    rc = regen_hound(HOUND, TEMPLATE, ts)
    if rc != 0:
        print("STOP: add_elint.py returned %d" % rc)
    return rc


def step_cas(dry, ts):
    """v1.4.0: CAS (L) = make_cas_l(deployed template)."""
    if dry:
        print("dry run: CAS (L) would be regenerated from %s" % TEMPLATE)
        return 0
    if os.path.isfile(CAS):
        backup(CAS, ts)
    rc = run([PY, os.path.join("tools", "make_cas_l.py"), TEMPLATE, CAS])
    if rc != 0:
        print("STOP: make_cas_l.py returned %d" % rc)
    return rc


def step_cas_hound(dry, ts):
    if not os.path.isfile(CAS):
        return 0
    if dry:
        print("dry run: CAS (L) HOUND would be regenerated from %s" % CAS)
        return 0
    rc = regen_hound(CAS_HOUND, CAS, ts)
    if rc != 0:
        print("STOP: add_elint.py (CAS HOUND) returned %d" % rc)
    return rc


def main():
    argv = sys.argv[1:]
    dry = "--dry-run" in argv
    ts = datetime.datetime.utcnow().strftime("%Y%m%d-%H%M%S")
    do_hound = "--skip-hound" not in argv
    do_cas = "--skip-cas" not in argv
    do_cas_hound = do_cas and "--skip-cas-hound" not in argv   # v1.2.0

    # v1.3.0: --step <name> runs one step (for shells with a per-call time limit). "guards" writes a token
    # (build/sync_guard.json, valid GUARD_MAX_S); the HOUND steps refuse without a fresh token unless forced.
    step = argv[argv.index("--step") + 1] if "--step" in argv and argv.index("--step") + 1 < len(argv) else None
    if step is not None and step not in STEPS:
        print("unknown --step %s (one of: %s)" % (step, ", ".join(STEPS)))
        return 2
    if step:
        import json
        if step == "guards":
            rc = step_guards(argv, do_hound, do_cas_hound, do_cas)
            if rc == 0 and not dry:
                os.makedirs(os.path.dirname(GUARD_TOKEN), exist_ok=True)
                with open(GUARD_TOKEN, "w") as f:
                    json.dump({"t": datetime.datetime.utcnow().timestamp(), "ts": ts}, f)
                print("guards passed, token %s (next: --step template, hound, cas, cas-hound)" % GUARD_TOKEN)
            return rc
        if step in ("hound", "cas", "cas-hound") and not dry:
            forced = {"hound": "--force-hound", "cas": "--force-cas", "cas-hound": "--force-cas-hound"}[step] in argv
            tok = None
            if os.path.isfile(GUARD_TOKEN):
                with open(GUARD_TOKEN) as f:
                    tok = json.load(f)
            if not forced and (not tok or datetime.datetime.utcnow().timestamp() - tok["t"] > GUARD_MAX_S):
                print("STOP: no fresh guard token; run --step guards first (before --step template)")
                return 2
            ts = tok["ts"] if tok else ts
        if step == "template":
            return step_template(argv, dry)
        if step == "hound":
            return step_hound(dry, ts) if do_hound else 0
        if step == "cas":
            return step_cas(dry, ts) if do_cas else 0
        rc = step_cas_hound(dry, ts) if do_cas_hound else 0
        if rc == 0 and not dry and os.path.isfile(GUARD_TOKEN):
            try:
                os.remove(GUARD_TOKEN)   # the sequence is complete
            except OSError:              # v1.3.1: a device shell without delete permission -> expire it instead
                with open(GUARD_TOKEN, "w") as f:
                    json.dump({"t": 0, "ts": "expired"}, f)
        if rc == 0:
            print("sync done (steps)")
        return rc

    # all steps in one go (Windows)
    for fn in (lambda: step_guards(argv, do_hound, do_cas_hound, do_cas),
               lambda: step_template(argv, dry),
               lambda: step_hound(dry, ts) if do_hound else 0,
               lambda: step_cas(dry, ts) if do_cas else 0,
               lambda: step_cas_hound(dry, ts) if do_cas_hound else 0):
        rc = fn()
        if rc != 0:
            return rc
    print("sync done" + (" (dry run)" if dry else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
