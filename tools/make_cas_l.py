# make_cas_l.py | v1.0.1
# v1.0.1: --accept-new also takes an unpacked mission file (src/mission).
# Generates "Close Air Support (L).miz" from the template .miz (decision Onur 2026-11-04 03:12: CAS (L) becomes a
# generated file like the HOUND variants; src/ is the only Mission Editor source). Before v1.0.0 CAS (L) was an
# own mission edited in its own ME session, and its ME layer drifted from the template (audit 2026-11-04, project
# doc claude/sync-audit-2026-11-04.md).
#
#   python tools/make_cas_l.py --init-spec <template.miz> <cas.miz>     # once: derive tools/cas_l_spec.json
#   python tools/make_cas_l.py <template.miz> <out.miz>                 # generate
#   python tools/make_cas_l.py --check <template.miz> <cas.miz>         # 0 if <cas.miz> == generate(<template.miz>)
#   python tools/make_cas_l.py --accept-new                             # NEW template groups -> known_groups
#
# CAS (L) = template minus (tools/cas_l_spec.json):
#   delete_groups    groups by name (RAT / civil traffic, base patrols, ambient units ...)
#   delete_triggers  trigger comments, "comment#n" = n-th trigger with that comment (duplicates)
#   delete_zones     trigger zones by name (ambient radio / ATIS / salute zones ...)
#   delete_drawings  [layer, object name]
# Derived, not listed: warehouses of deleted units; mapResource entries and l10n/DEFAULT files no kept content
# references (RAT scripts, ambient radio / ATIS clips). The dictionary is kept whole (unreferenced keys are inert).
# Trigger indices are renumbered in trigrules and in the compiled trig strings (mission.trig.func[i] ...).
# Template groups that are in neither delete_groups nor known_groups are NEW: they go into CAS (L) and are reported;
# delete them (add to delete_groups) or accept them (--accept-new).
# Checks before writing: every unit / group / zone id referenced by kept triggers, kept routes (linkUnit, helipadId,
# task groupId / unitId) exists. Ignored in --check: map view, currentKey, maxDictId, options (audio device ids),
# ResKey numbering (compared by file name), unreferenced dictionary keys.

import argparse
import copy
import json
import os
import re
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, ".."))
sys.path.insert(0, REPO)
import dcslua  # noqa: E402

SPEC = os.path.join(HERE, "cas_l_spec.json")
CATS = (b"plane", b"helicopter", b"vehicle", b"ship", b"static")
MAPRES = "l10n/DEFAULT/mapResource"
DICT = "l10n/DEFAULT/dictionary"
TRIG_REF = re.compile(rb"mission\.trig\.(func|conditions|actions|flag)\[(\d+)\]")


def d(v):
    return dcslua.dump("x", {1: v})


def S(b):
    return b.decode("utf-8", "replace") if isinstance(b, bytes) else str(b)


def read(z, name):
    return dcslua.parse(z.read(name))


def iter_groups(m):
    for side, cs in m[b"coalition"].items():
        for c in (cs.get(b"country") or {}).values():
            for cat in CATS:
                gt = (c.get(cat) or {}).get(b"group") or {}
                for gi, g in gt.items():
                    yield side, c, cat, gi, g


def trig_keys(m):
    """[(index, key)] in order; key = comment or comment#n for the n-th duplicate."""
    seen, out = {}, []
    for i in sorted(m[b"trigrules"]):
        c = S(m[b"trigrules"][i].get(b"comment", b""))
        seen[c] = seen.get(c, 0) + 1
        out.append((i, c if seen[c] == 1 else "%s#%d" % (c, seen[c])))
    # rename first of a duplicated comment to #1 only if a #2 exists: keep plain name (stable for unique ones)
    return out


def drawing_objs(m):
    for li, l in (m.get(b"drawings", {}).get(b"layers") or {}).items():
        for oi, o in (l.get(b"objects") or {}).items():
            yield li, l, oi, o


# ------------------------------------------------------------------ generate
def generate(tpl_path, spec, report):
    zt = zipfile.ZipFile(tpl_path)
    name, m = read(zt, "mission")
    m = copy.deepcopy(m)
    dg, dz = set(spec["delete_groups"]), set(spec["delete_zones"])
    dtr, ddr = set(spec["delete_triggers"]), set(tuple(x) for x in spec["delete_drawings"])
    known = set(spec["known_groups"])

    # groups
    deleted_units, deleted_groups, new = set(), set(), []
    country_groups_before = {}
    for side, cs in m[b"coalition"].items():
        for c in (cs.get(b"country") or {}).values():
            country_groups_before[id(c)] = [g for cat in CATS for g in ((c.get(cat) or {}).get(b"group") or {}).values()]
    for side, cs in m[b"coalition"].items():
        for c in (cs.get(b"country") or {}).values():
            for cat in CATS:
                tab = c.get(cat)
                if not tab or not tab.get(b"group"):
                    continue
                keep = []
                for gi in sorted(tab[b"group"]):
                    g = tab[b"group"][gi]
                    gn = S(g[b"name"])
                    if gn in dg:
                        deleted_groups.add(g[b"groupId"])
                        deleted_units.update(u[b"unitId"] for u in g[b"units"].values())
                    else:
                        if gn not in known:
                            new.append(gn)
                        keep.append(g)
                if keep:
                    tab[b"group"] = {i + 1: g for i, g in enumerate(keep)}
                else:                       # the ME drops a category whose last group was deleted
                    del c[cat]
        # ... and a country left without any category (renumbered)
        if cs.get(b"country"):
            cl = [cs[b"country"][k] for k in sorted(cs[b"country"])]
            cl2 = [c for c in cl if any(c.get(cat) for cat in CATS) or not any(
                S(g[b"name"]) in dg for g in country_groups_before.get(id(c), []))]
            cs[b"country"] = {i + 1: c for i, c in enumerate(cl2)}
    missing = sorted(dg - set(S(g[b"name"]) for *_, g in iter_groups(dcslua.parse(zt.read("mission"))[1])))
    report["new_groups"], report["spec_groups_not_in_template"] = new, missing

    # zones
    zones = m[b"triggers"][b"zones"]
    kept_z = [zones[k] for k in sorted(zones) if S(zones[k][b"name"]) not in dz]
    deleted_zone_ids = set(zones[k][b"zoneId"] for k in zones if S(zones[k][b"name"]) in dz)
    m[b"triggers"][b"zones"] = {i + 1: z for i, z in enumerate(kept_z)}

    # drawings
    for l in (m.get(b"drawings", {}).get(b"layers") or {}).values():
        objs = l.get(b"objects") or {}
        kept_o = [objs[k] for k in sorted(objs) if (S(l[b"name"]), S(objs[k].get(b"name"))) not in ddr]
        if len(kept_o) != len(objs):
            l[b"objects"] = {i + 1: o for i, o in enumerate(kept_o)}

    # triggers
    keys = trig_keys(m)
    kept = [i for i, k in keys if k not in dtr]
    report["spec_triggers_not_in_template"] = sorted(dtr - set(k for _, k in keys))
    renum = {old: new_i + 1 for new_i, old in enumerate(kept)}
    tr, tg = m[b"trigrules"], m[b"trig"]
    m[b"trigrules"] = {renum[i]: tr[i] for i in kept}

    def fix(s):
        if not isinstance(s, bytes):
            return s

        def rep(mm):
            old = int(mm.group(2))
            if old not in renum:
                raise SystemExit("compiled trigger string refers to deleted trigger %d: %r" % (old, s[:120]))
            return b"mission.trig.%s[%d]" % (mm.group(1), renum[old])
        return TRIG_REF.sub(rep, s)

    for sub in list(tg):
        v = tg[sub]
        if isinstance(v, dict) and v:
            tg[sub] = {renum[i]: fix(v[i]) for i in sorted(v) if i in renum}

    # reference checks
    unit_ids = set(u[b"unitId"] for *_, g in iter_groups(m) for u in g[b"units"].values())
    group_ids = set(g[b"groupId"] for *_, g in iter_groups(m))
    zone_ids = set(z[b"zoneId"] for z in m[b"triggers"][b"zones"].values())
    errs = []

    def walk(node, path):
        if isinstance(node, dict):
            for k, v in node.items():
                ks = S(k)
                if isinstance(v, int) and not isinstance(v, bool):
                    if ks in ("linkUnit", "helipadId", "unitId") and v in deleted_units:
                        errs.append("%s/%s -> deleted unit %d" % (path, ks, v))
                    if ks == "groupId" and v in deleted_groups:
                        errs.append("%s/%s -> deleted group %d" % (path, ks, v))
                    if ks == "zone" and v in deleted_zone_ids:
                        errs.append("%s/%s -> deleted zone %d" % (path, ks, v))
                walk(v, path + "/" + ks)
    for side, c, cat, gi, g in iter_groups(m):
        walk(g.get(b"route", {}), "group %s route" % S(g[b"name"]))
    for i, r in m[b"trigrules"].items():
        for part in (b"rules", b"actions"):
            for x in (r.get(part) or {}).values():
                for key, ids in ((b"group", deleted_groups), (b"unit", deleted_units), (b"zone", deleted_zone_ids)):
                    if isinstance(x.get(key), int) and x[key] in ids:
                        errs.append("trigger %s %s %s -> deleted %d" % (S(r.get(b"comment")), S(x.get(b"predicate")),
                                                                     S(key), x[key]))
                at = x.get(b"ai_task")
                if isinstance(at, dict) and at.get(1) in deleted_groups:
                    errs.append("trigger %s ai_task -> deleted group %d" % (S(r.get(b"comment")), at[1]))
    if errs:
        raise SystemExit("reference check failed:\n  " + "\n  ".join(errs[:30]))

    # warehouses of deleted units
    wname, w = read(zt, "warehouses")
    w = copy.deepcopy(w)
    wh = w.get(b"warehouses") or {}
    w[b"warehouses"] = {k: v for k, v in wh.items() if k not in deleted_units}

    # mapResource: referenced keys only; l10n files they name
    mname, mr = read(zt, MAPRES)
    refs = set(re.findall(rb"ResKey_[A-Za-z]+_\d+", dcslua.dump("m", m)))
    mr2 = {k: v for k, v in mr.items() if k in refs}
    keep_files = set("l10n/DEFAULT/" + S(v) for v in mr2.values())
    drop_files = set("l10n/DEFAULT/" + S(v) for k, v in mr.items() if k not in refs) - keep_files
    report["dropped_files"] = sorted(drop_files)
    report["triggers"] = (len(keys), len(kept))
    report["groups_deleted"] = len(deleted_groups)
    out = {"mission": dcslua.dump(S(name), m), "warehouses": dcslua.dump(S(wname), w),
           MAPRES: dcslua.dump(S(mname), mr2)}
    return zt, out, drop_files


def write(zt, out, drop_files, path):
    tmp = path + ".tmp"
    with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as zo:
        for info in zt.infolist():
            if info.filename in drop_files:
                continue
            zo.writestr(info, out[info.filename] if info.filename in out else zt.read(info.filename))
    with zipfile.ZipFile(tmp) as t:
        bad = t.testzip()
        if bad:
            os.remove(tmp)
            raise SystemExit("zip test failed on %s" % bad)
    os.replace(tmp, path)


# ------------------------------------------------------------------ semantic compare
def semantic(files):
    """files: dict name -> bytes for mission / warehouses / mapResource / dictionary + entry list."""
    _, m = dcslua.parse(files["mission"])
    _, mr = dcslua.parse(files[MAPRES])
    m = copy.deepcopy(m)
    for k in (b"map", b"currentKey", b"maxDictId"):
        m.pop(k, None)
    blob = dcslua.dump("m", m)
    blob = re.sub(rb"ResKey_[A-Za-z]+_\d+", lambda x: b"RES:" + mr.get(x.group(0), b"?" + x.group(0)), blob)
    _, w = dcslua.parse(files["warehouses"])
    return {"mission": blob, "warehouses": dcslua.dump("w", w),
            "mapResource": sorted(mr.values()), "entries": files["entries"]}


def zip_files(z, out=None, drop=()):
    f = {n: (out or {}).get(n) or z.read(n) for n in ("mission", "warehouses", MAPRES)}
    f["entries"] = sorted(n for n in z.namelist() if n not in drop)
    return f


def check(tpl, cas, spec):
    rep = {}
    zt, out, drop = generate(tpl, spec, rep)
    a = semantic(zip_files(zt, out, drop))
    zc = zipfile.ZipFile(cas)
    b = semantic(zip_files(zc))
    diffs = []
    for k in a:
        if a[k] != b[k]:
            if k == "entries":   # not ME data: everything outside mission / warehouses / mapResource comes from
                sa, sb = set(a[k]), set(b[k])   # the template anyway -> reported, not a difference
                rep["entries_note"] = "only generated %s / only %s %s" % (sorted(sa - sb)[:8], os.path.basename(cas),
                                                                          sorted(sb - sa)[:8])
            elif k == "mission":
                la, lb = S(a[k]).split("\n"), S(b[k]).split("\n")
                import difflib
                dl = list(difflib.unified_diff(la, lb, lineterm="", n=1))
                diffs.append("mission: %d diff lines\n    " % len(dl) +
                             "\n    ".join(x[:150] for x in dl[:40]))
            else:
                diffs.append(k + " differs")
    # dictionary: every key the CAS has must exist with the same value in the template
    _, dt = read(zt, DICT)
    _, dc = read(zc, DICT)
    bad = [k for k in dc if dt.get(k) != dc[k]]
    if bad:
        diffs.append("dictionary: %d keys differ/missing in template, e.g. %s" % (len(bad), bad[:5]))
    return rep, diffs


# ------------------------------------------------------------------ main
def init_spec(tpl, cas):
    zt, zc = zipfile.ZipFile(tpl), zipfile.ZipFile(cas)
    _, t = read(zt, "mission")
    _, c = read(zc, "mission")
    cg = set(S(g[b"name"]) for *_, g in iter_groups(c))
    tgn = [S(g[b"name"]) for *_, g in iter_groups(t)]
    if len(set(tgn)) != len(tgn):
        raise SystemExit("duplicate group names in the template")
    ckeys = [k for _, k in trig_keys(c)]
    tkeys = [k for _, k in trig_keys(t)]
    it = iter(tkeys)
    if not all(k in it for k in ckeys):
        raise SystemExit("CAS (L) triggers are not an ordered subset of the template's")
    cz = set(S(z[b"name"]) for z in c[b"triggers"][b"zones"].values())
    cd = set((S(l[b"name"]), S(o.get(b"name"))) for _, l, _, o in drawing_objs(c))
    spec = {
        "_comment": "make_cas_l.py spec. Close Air Support (L) = template minus these. Edit by hand; "
                    "known_groups = every template group at the last --init-spec / --accept-new.",
        "delete_groups": sorted(n for n in tgn if n not in cg),
        "delete_triggers": [k for k in tkeys if k not in set(ckeys)],
        "delete_zones": sorted(S(z[b"name"]) for z in t[b"triggers"][b"zones"].values() if S(z[b"name"]) not in cz),
        "delete_drawings": sorted([S(l[b"name"]), S(o.get(b"name"))] for _, l, _, o in drawing_objs(t)
                                  if (S(l[b"name"]), S(o.get(b"name"))) not in cd),
        "known_groups": sorted(tgn),
    }
    with open(SPEC, "w", encoding="utf-8") as f:
        json.dump(spec, f, indent=1, ensure_ascii=False)
        f.write("\n")
    print("spec written: %d groups, %d triggers, %d zones, %d drawings to delete"
          % (len(spec["delete_groups"]), len(spec["delete_triggers"]), len(spec["delete_zones"]),
             len(spec["delete_drawings"])))


def load_spec():
    with open(SPEC, encoding="utf-8") as f:
        return json.load(f)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--init-spec", action="store_true")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--accept-new", metavar="TEMPLATE_MIZ_OR_MISSION")
    ap.add_argument("paths", nargs="*")
    a = ap.parse_args()
    if a.init_spec:
        return init_spec(*a.paths)
    if a.accept_new:
        spec = load_spec()
        if a.accept_new.lower().endswith(".miz"):
            _, t = read(zipfile.ZipFile(a.accept_new), "mission")
        else:                                   # v1.0.1: an unpacked mission file (src/mission)
            _, t = dcslua.parse(open(a.accept_new, "rb").read())
        names = set(S(g[b"name"]) for *_, g in iter_groups(t))
        add = sorted(names - set(spec["known_groups"]))
        spec["known_groups"] = sorted(set(spec["known_groups"]) | names)
        with open(SPEC, "w", encoding="utf-8") as f:
            json.dump(spec, f, indent=1, ensure_ascii=False)
            f.write("\n")
        print("accepted %d new group(s): %s" % (len(add), add))
        return 0
    spec = load_spec()
    if a.check:
        rep, diffs = check(a.paths[0], a.paths[1], spec)
        for k, v in rep.items():
            print("%s: %s" % (k, v))
        if diffs:
            print("DIFFERENT:\n  " + "\n  ".join(diffs))
            return 1
        print("same: %s == generate(%s)" % (os.path.basename(a.paths[1]), os.path.basename(a.paths[0])))
        return 0
    rep = {}
    zt, out, drop = generate(a.paths[0], spec, rep)
    for k, v in rep.items():
        print("%s: %s" % (k, v))
    if rep["new_groups"]:
        print("NOTE: %d NEW template group(s) included in CAS (L): %s  (delete_groups or --accept-new)"
              % (len(rep["new_groups"]), rep["new_groups"][:20]))
    write(zt, out, drop, a.paths[1])
    print("written: %s" % a.paths[1])
    return 0


if __name__ == "__main__":
    sys.exit(main() or 0)
