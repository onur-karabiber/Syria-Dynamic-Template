# port_cas_me.py | v1.0.0
# ONE-OFF (2026-11-04): superseded the same night by tools/make_cas_l.py (CAS (L) is now generated from the
# template and must not be edited in the ME). Kept for the record; running it again reports "no change".
# Carries Mission Editor changes made in Close Air Support (L).miz into the template (src/mission).
# Audit 2026-11-04 (project doc claude/sync-audit-2026-11-04.md): scripts and media were in step in all four
# missions, the ME layer was not; CAS (L) was ahead. Decision Onur 2026-11-04 02:46: everything below goes into
# the template, CAP positions and INTER-2 range included. Idempotent: a second run reports "no change".
#
#   python tools/port_cas_me.py [--dry-run] [--cas "<path>/Close Air Support (L).miz"]
#   then: python tools/sync_missions.py   (builds the template, regenerates both HOUND variants)
#
# What is ported (source = the deployed CAS (L), read only):
#   1. GROUPS: the whole group table, replaced by name. Refused unless coalition / country / category / groupId /
#      unitIds are identical in both missions (same unit, edited in one ME only).
#        CAS-1 (IP LYNX / IP PUMA waypoints), JTAC-1, JTAC-2 and their targets SAM BV51 (SA-13)-1 (+ camouflage),
#        SAM YE53 (SA-8)-1 (+ camouflage 1-3), CAP-1 / CAP-2 (orbits clear of the SAM umbrella, 25 NM), INTER-2
#        (25 NM), Random-1 / Random-3 / CIVIL-2 (ME-computed ETAs only).
#   2. ZONES: SA8_3 (moved with the SA-8); every field except zoneId.
#   3. TRIGGER Tanker_Defenders_Activate: condition "red in TANKER_DEFENDERS_ZONE" -> flag 3011 (Asset_Guard:
#      hostile FIGHTER airborne in the zone; the zone condition also fired on red ground units). trigrules rules
#      and the compiled trig.conditions string, both.
#   4. TRIGGER OWN_SCRIPTS: Do Script File order as in CAS (L) (template had Flight_Timeline before
#      PlaneCaptain_Carrier, against Flight_Timeline's load-order note). Template ResKeys are kept and only
#      reordered (the ResKey -> file numbering differs between the two missions); trig.actions rebuilt.
# Not ported (intentional template-only content): RAT, ambient radios, ATIS, base patrols, Salute/Directives,
# DEAD SCORE triggers, the second Activate_Civil-4 (group deleted in CAS (L)), drawing Author/Arming_incirlik.

import argparse
import copy
import os
import re
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, ".."))
sys.path.insert(0, REPO)
import config  # noqa: E402
import dcslua  # noqa: E402

GROUPS = ["CAS-1", "JTAC-1", "JTAC-2",
          "SAM BV51 (SA-13)-1", "SAM BV51 (SA-13)-1-Camouflage-1",
          "SAM YE53 (SA-8)-1", "SAM YE53 (Camouflage)-1", "SAM YE53 (Camouflage)-2", "SAM YE53 (Camouflage)-3",
          "CAP-1", "CAP-2", "INTER-2", "Random-1", "Random-3", "CIVIL-2"]
ZONES = ["SA8_3"]
TRG_TANKER = b"Tanker_Defenders_Activate"
TRG_SCRIPTS = b"OWN_SCRIPTS"
SRC_MISSION = os.path.join(REPO, "src", "mission")
SRC_MAPRES = os.path.join(REPO, "src", "l10n", "DEFAULT", "mapResource")


def dump1(v):
    return dcslua.dump("x", {1: v})


def groups(m):
    out = {}
    for side, cs in m[b"coalition"].items():
        for c in (cs.get(b"country") or {}).values():
            for cat in (b"plane", b"helicopter", b"vehicle", b"ship", b"static"):
                gtab = (c.get(cat) or {}).get(b"group") or {}
                for gi, gr in gtab.items():
                    out.setdefault(gr[b"name"], []).append((side, c[b"name"], cat, gtab, gi))
    return out


def ids(gr):
    return gr[b"groupId"], tuple(u[b"unitId"] for _, u in sorted(gr[b"units"].items()))


def rule_index(m, comment):
    hits = [i for i, r in m[b"trigrules"].items() if r.get(b"comment") == comment]
    if len(hits) != 1:
        sys.exit("expected one trigger %r, found %d" % (comment, len(hits)))
    return hits[0]


def port(t, c, map_t, map_c):
    changes = []
    # ---- 1. groups
    gt, gc = groups(t), groups(c)
    for name in GROUPS:
        n = name.encode()
        if len(gt.get(n, [])) != 1 or len(gc.get(n, [])) != 1:
            sys.exit("group %s: expected one in each mission (template %d, CAS %d)"
                     % (name, len(gt.get(n, [])), len(gc.get(n, []))))
        st, sc = gt[n][0], gc[n][0]
        tgr, cgr = st[3][st[4]], sc[3][sc[4]]
        if st[:3] != sc[:3] or ids(tgr) != ids(cgr):
            sys.exit("group %s: different unit in the two missions (%s %s / %s %s), refused"
                     % (name, st[:3], ids(tgr), sc[:3], ids(cgr)))
        if dump1(tgr) != dump1(cgr):
            st[3][st[4]] = copy.deepcopy(cgr)
            changes.append("group %s replaced from CAS (L)" % name)
    # ---- 2. zones
    zt = {z[b"name"]: z for z in t[b"triggers"][b"zones"].values()}
    zc = {z[b"name"]: z for z in c[b"triggers"][b"zones"].values()}
    for name in ZONES:
        a, b = zt[name.encode()], zc[name.encode()]
        for k, v in b.items():
            if k != b"zoneId" and a.get(k) != v:
                a[k] = copy.deepcopy(v)
                changes.append("zone %s %s" % (name, k.decode()))
    # ---- 3. Tanker_Defenders_Activate condition
    it, ic = rule_index(t, TRG_TANKER), rule_index(c, TRG_TANKER)
    rt, rc = t[b"trigrules"][it], c[b"trigrules"][ic]
    if dump1(rt[b"rules"]) != dump1(rc[b"rules"]):
        rt[b"rules"] = copy.deepcopy(rc[b"rules"])
        changes.append("trigger %s rules -> %s" % (TRG_TANKER.decode(), rc[b"rules"][1].get(b"predicate").decode()))
    cond_c = c[b"trig"][b"conditions"][ic]
    if t[b"trig"][b"conditions"][it] != cond_c:
        t[b"trig"][b"conditions"][it] = cond_c
        changes.append("trig.conditions[%d] -> %s" % (it, cond_c.decode()))
    # ---- 4. OWN_SCRIPTS order
    it, ic = rule_index(t, TRG_SCRIPTS), rule_index(c, TRG_SCRIPTS)
    at = t[b"trigrules"][it][b"actions"]
    ac = c[b"trigrules"][ic][b"actions"]
    by_file = {}
    for _, a in sorted(at.items()):
        if a.get(b"predicate") != b"a_do_script_file":
            sys.exit("OWN_SCRIPTS: unexpected action %r in the template" % a.get(b"predicate"))
        by_file[map_t[a[b"file"]]] = a
    order_c = [map_c[a[b"file"]] for _, a in sorted(ac.items())]
    order_t = [map_t[a[b"file"]] for _, a in sorted(at.items())]
    if sorted(order_c) != sorted(order_t):
        sys.exit("OWN_SCRIPTS: different script sets (template only %s, CAS only %s)"
                 % (sorted(set(order_t) - set(order_c)), sorted(set(order_c) - set(order_t))))
    old_str = t[b"trig"][b"actions"][it]
    expect = b"".join(b'a_do_script_file(getValueResourceByKey("%s"));' % a[b"file"] for _, a in sorted(at.items()))
    if old_str != expect:
        sys.exit("OWN_SCRIPTS: trig.actions[%d] is not the plain list this tool rebuilds, refused:\n%r" % (it, old_str))
    if order_t != order_c:
        new = {i + 1: by_file[f] for i, f in enumerate(order_c)}
        t[b"trigrules"][it][b"actions"] = new
        t[b"trig"][b"actions"][it] = b"".join(
            b'a_do_script_file(getValueResourceByKey("%s"));' % a[b"file"] for _, a in sorted(new.items()))
        changes.append("OWN_SCRIPTS order -> CAS (L): " + ", ".join(f.decode() for f in order_c))
    return changes


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--cas", default=os.path.join(config.MISSIONS_DIR, "Close Air Support (L).miz"))
    a = ap.parse_args()
    with open(SRC_MISSION, "rb") as f:
        name, t = dcslua.parse(f.read())
    with open(SRC_MAPRES, "rb") as f:
        map_t = dcslua.parse(f.read())[1]
    with zipfile.ZipFile(a.cas) as z:
        c = dcslua.parse(z.read("mission"))[1]
        map_c = dcslua.parse(z.read("l10n/DEFAULT/mapResource"))[1]
    changes = port(t, c, map_t, map_c)
    for ch in changes:
        print("  " + ch)
    if not changes:
        print("src/mission: no change")
        return
    if a.dry_run:
        print("dry run: src/mission not written (%d change(s))" % len(changes))
        return
    out = dcslua.dump(name, t)
    if dcslua.parse(out)[1] is None:
        sys.exit("re-parse failed, not written")
    with open(SRC_MISSION, "wb") as f:
        f.write(out)
    print("written: src/mission (%d change(s)); next: python tools/sync_missions.py" % len(changes))


if __name__ == "__main__":
    main()
