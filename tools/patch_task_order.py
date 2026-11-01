# patch_task_order.py | v1.0.0
# Moves waypoint COMMANDS (WrappedAction: SetUnlimitedFuel, ActivateBeacon, Option ...)
# ahead of the first long-running main task (Follow, RecoveryTanker, Orbit ...) in the
# listed groups. DCS runs a waypoint's task list in order and a main task without a
# stop condition never completes, so commands placed after it are never executed.
# Found 2026-10-31: Plane_Guard-1 (SH-60B) Follow -> SetUnlimitedFuel never ran, the
# helo ran out of fuel after ~2 h 20 min, landed on the CVN landing area -> AIRBOSS
# "Foul deck" waveoffs. TANKER-3 had the same order (RecoveryTanker -> TACAN 23Y beacon,
# Option, SetUnlimitedFuel). Idempotent: a second run reports "no change".
#
#   python tools/patch_task_order.py --src [--dry-run]          # src/mission, then build.py
#   python tools/patch_task_order.py "<path>.miz" [--dry-run]   # a .miz IN PLACE (CAS (L)),
#                                                                # backup -> <dir>/BackUps/
# Other groups with the same pattern are only REPORTED (red CAP Options after Orbit):
# moving them changes adversary behaviour and is a separate decision.

import datetime
import os
import shutil
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, ".."))
sys.path.insert(0, REPO)
import dcslua  # noqa: E402

GROUPS = (b"Plane_Guard-1", b"TANKER-3")
BLOCKING = {b"Follow", b"Orbit", b"RecoveryTanker", b"Escort", b"Hold", b"Land", b"FollowBigFormation",
            b"AttackGroup", b"AttackUnit", b"Bombing", b"BombingRunway", b"CarpetBombing", b"AttackMapObject"}


def s(x):
    return x.decode() if isinstance(x, bytes) else str(x)


def label(t):
    if t.get(b"id") == b"WrappedAction":
        return "CMD:" + s(t[b"params"][b"action"][b"id"])
    return s(t.get(b"id"))


def reorder(tasks):
    """Returns the new ordered list or None when nothing changes."""
    seq = [tasks[k] for k in sorted(tasks)]
    first = next((i for i, t in enumerate(seq) if t.get(b"id") in BLOCKING), None)
    if first is None:
        return None
    late = [t for t in seq[first + 1:] if t.get(b"id") == b"WrappedAction"]
    if not late:
        return None
    rest = [t for t in seq[first:] if t.get(b"id") != b"WrappedAction"]
    early_cmds = [t for t in seq[first:] if t.get(b"id") == b"WrappedAction"]
    return seq[:first] + early_cmds + rest


def patch(m):
    changes, report = [], []
    for side in m[b"coalition"].values():
        for c in side[b"country"].values():
            for cat in (b"plane", b"helicopter"):
                for g in c.get(cat, {}).get(b"group", {}).values():
                    for i, p in sorted(g[b"route"][b"points"].items()):
                        tp = p.get(b"task", {}).get(b"params", {})
                        tasks = tp.get(b"tasks")
                        if not tasks:
                            continue
                        new = reorder(tasks)
                        if new is None:
                            continue
                        before = [label(tasks[k]) for k in sorted(tasks)]
                        if g[b"name"] not in GROUPS:
                            report.append("%s WP%d %s" % (s(g[b"name"]), i, before))
                            continue
                        tp[b"tasks"] = {}
                        for n, t in enumerate(new, 1):
                            t[b"number"] = n
                            tp[b"tasks"][n] = t
                        changes.append("%s WP%d %s -> %s" % (s(g[b"name"]), i, before, [label(t) for t in new]))
    return changes, report


def show(changes, report):
    for c in changes:
        print("  " + c)
    for r in report:
        print("  NOT CHANGED (report only): " + r)


def run_src(dry):
    path = os.path.join(REPO, "src", "mission")
    with open(path, "rb") as f:
        name, m = dcslua.parse(f.read())
    changes, report = patch(m)
    show(changes, report)
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
        changes, report = patch(m)
        show(changes, report)
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
        backup = os.path.join(bdir, "%s_before-task-order-%s.miz" % (os.path.splitext(os.path.basename(miz))[0], stamp))
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
        sys.exit("usage: patch_task_order.py --src | <file.miz> [--dry-run]")
