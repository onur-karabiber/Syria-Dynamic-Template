# strip_native_jtac.py | v1.0.0
# Removes the native DCS JTAC tasks (FAC, FAC_AttackGroup, FAC_EngageGroup, FAC_AttackUnit)
# from the route tasks of the named ground groups, so that JTAC_Controller is the only JTAC
# talking on their frequencies (plan claude/jtac-plan-2026-10-29.md, J2). Other route tasks
# (SetInvisible / SetImmortal / ROE wrapped actions) are kept and renumbered.
#
#   python tools/strip_native_jtac.py --miz "<...>/Close Air Support (L).miz" JTAC-1 JTAC-2 [--dry-run]
#       -> backup BackUps/<name>_before-strip-jtac-<YYYYmmdd-HHMMSS>.miz, then the edited mission
#   python tools/strip_native_jtac.py --src JTAC-1 JTAC-2 [--dry-run]
#       -> edits src/mission (then: python build.py)
# Everything else in the .miz is copied unchanged.

import argparse
import io
import os
import shutil
import sys
import time
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, ".."))
sys.path.insert(0, REPO)
import dcslua  # noqa: E402

FAC_IDS = {b"FAC", b"FAC_AttackGroup", b"FAC_EngageGroup", b"FAC_AttackUnit"}


def resolve(v, dct):
    if isinstance(v, bytes) and v.startswith(b"DictKey_") and dct:
        return dct.get(v, v)
    return v


def strip(mission, names, dct=None):
    want = {n.encode() for n in names}
    found = set()
    removed = 0
    for side in mission[b"coalition"].values():
        for c in side.get(b"country", {}).values():
            for g in c.get(b"vehicle", {}).get(b"group", {}).values():
                gn = resolve(g.get(b"name"), dct)
                if gn not in want:
                    continue
                found.add(gn)
                for pi, p in sorted(g.get(b"route", {}).get(b"points", {}).items()):
                    tasks = p.get(b"task", {}).get(b"params", {}).get(b"tasks")
                    if not tasks:
                        continue
                    keep = [t for _, t in sorted(tasks.items()) if t.get(b"id") not in FAC_IDS]
                    gone = [t.get(b"id").decode() for _, t in sorted(tasks.items()) if t.get(b"id") in FAC_IDS]
                    if not gone:
                        continue
                    new = {}
                    for i, t in enumerate(keep, 1):
                        t[b"number"] = i
                        new[i] = t
                    p[b"task"][b"params"][b"tasks"] = new
                    removed += len(gone)
                    print("%s point %d: removed %s, kept %d task(s)" % (gn.decode(), pi, ", ".join(gone), len(keep)))
    for n in want - found:
        print("WARN group not found:", n.decode())
    return removed


def do_src(names, dry):
    mp = os.path.join(REPO, "src", "mission")
    dp = os.path.join(REPO, "src", "l10n", "DEFAULT", "dictionary")
    _, mission = dcslua.parse(open(mp, "rb").read())
    dct = dcslua.parse(open(dp, "rb").read())[1] if os.path.isfile(dp) else None
    n = strip(mission, names, dct)
    if dry or n == 0:
        print("dry run" if dry else "nothing to remove")
        return
    open(mp, "wb").write(dcslua.dump("mission", mission))
    print("src/mission updated - run: python build.py")


def do_miz(miz, names, dry):
    zin = zipfile.ZipFile(miz)
    _, mission = dcslua.parse(zin.read("mission"))
    dname = "l10n/DEFAULT/dictionary"
    dct = dcslua.parse(zin.read(dname))[1] if dname in zin.namelist() else None
    n = strip(mission, names, dct)
    if dry or n == 0:
        print("dry run" if dry else "nothing to remove")
        zin.close()
        return
    bdir = os.path.join(os.path.dirname(miz), "BackUps")
    os.makedirs(bdir, exist_ok=True)
    backup = os.path.join(bdir, "%s_before-strip-jtac-%s.miz" % (
        os.path.splitext(os.path.basename(miz))[0], time.strftime("%Y%m%d-%H%M%S")))
    shutil.copy2(miz, backup)
    print("backup", backup)
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zout:
        for nm in zin.namelist():
            if nm == "mission":
                continue
            zout.writestr(zin.getinfo(nm), zin.read(nm))
        zout.writestr("mission", dcslua.dump("mission", mission))
    zin.close()
    with open(miz, "wb") as f:
        f.write(buf.getvalue())
    print("written", miz, os.path.getsize(miz), "bytes")


def main():
    ap = argparse.ArgumentParser(description="remove native DCS JTAC (FAC) tasks from ground groups")
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--src", action="store_true", help="edit the unpacked template in src/")
    g.add_argument("--miz", help="edit this .miz in place (after a backup)")
    ap.add_argument("groups", nargs="+", help="ME group names, e.g. JTAC-1 JTAC-2")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    if a.src:
        do_src(a.groups, a.dry_run)
    else:
        do_miz(a.miz, a.groups, a.dry_run)


if __name__ == "__main__":
    main()
